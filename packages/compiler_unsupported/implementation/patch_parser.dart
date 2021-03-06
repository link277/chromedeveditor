// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This library contains the infrastructure to parse and integrate patch files.
 *
 * Three types of elements can be patched: [LibraryElement], [ClassElement],
 * [FunctionElement]. Patches are introduced in patch libraries which are loaded
 * together with the corresponding origin library. Which libraries that are
 * patched is determined by the dart2jsPatchPath field of LibraryInfo found
 * in [:lib/_internal/libraries.dart:].
 *
 * Patch libraries are parsed like regular library and thus provided with their
 * own elements. These elements which are distinct from the elements from the
 * patched library and the relation between patched and patch elements is
 * established through the [:patch:] and [:origin:] fields found on
 * [LibraryElement], [ClassElement] and [FunctionElement]. The [:patch:] fields
 * are set on the patched elements to point to their corresponding patch
 * element, and the [:origin:] elements are set on the patch elements to point
 * their corresponding patched elements.
 *
 * The fields [Element.isPatched] and [Element.isPatch] can be used to determine
 * whether the [:patch:] or [:origin:] field, respectively, has been set on an
 * element, regardless of whether the element is one of the three patchable
 * element types or not.
 *
 * ## Variants of classes and functions ##
 *
 * With patches there are four variants of classes and function:
 *
 * Regular: A class or function which is not declared in a patch library and
 *   which has no corresponding patch.
 * Origin: A class or function which is not declared in a patch library and
 *   which has a corresponding patch. Origin functions must use the [:external:]
 *   modifier and can have no body. Origin classes and functions are also
 *   called 'patched'.
 * Patch: A class or function which is declared in a patch library and which
 *   has a corresponding origin. Both patch classes and patch functions must use
 *   the [:patch:] modifier.
 * Injected: A class or function (or even field) which is declared in a
 *   patch library and which has no corresponding origin. An injected element
 *   cannot use the [:patch:] modifier. Injected elements are never visible from
 *   outside the patch library in which they have been declared. For this
 *   reason, injected elements are often declared private and therefore called
 *   also called 'patch private'.
 *
 * Examples of the variants is shown in the code below:
 *
 *     // In the origin library:
 *     class RegularClass { // A regular class.
 *       void regularMethod() {} // A regular method.
 *     }
 *     class PatchedClass { // An origin class.
 *       int regularField; // A regular field.
 *       void regularMethod() {} // A regular method.
 *       external void patchedMethod(); // An origin method.
 *     }
 *
 *     // In the patch library:
 *     class _InjectedClass { // An injected class.
 *       void _injectedMethod() {} // An injected method.
 *     }
 *     @patch class PatchedClass { // A patch class.
 *       int _injectedField; { // An injected field.
 *       @patch void patchedMethod() {} // A patch method.
 *     }
 *
 *
 * ## Declaration and implementation ##
 *
 * With patches we have two views on elements: as the 'declaration' which
 * introduces the entity and defines its interface, and as the 'implementation'
 * which defines the actual implementation of the entity.
 *
 * Every element has a 'declaration' and an 'implementation' element. For
 * regular and injected elements these are the same. For origin elements the
 * declaration is the element itself and the implementation is the patch element
 * found through its [:patch:] field. For patch elements the implementation is
 * the element itself and the declaration is the origin element found through
 * its [:origin:] field. The declaration and implementation of any element is
 * conveniently available through the [Element.declaration] and
 * [Element.implementation] getters.
 *
 * Most patch-related invariants enforced through-out the compiler are defined
 * in terms of 'declaration' and 'implementation', and tested through the
 * predicate getters [Element.isDeclaration] and [Element.isImplementation].
 * Patch invariants are stated both in comments and as assertions.
 *
 *
 * ## General invariant guidelines ##
 *
 * For [LibraryElement] we always use declarations. This means the
 * [Element.getLibrary] method will only return library declarations. Patch
 * library implementations are only accessed through calls to
 * [Element.getImplementationLibrary] which is used to setup the correct
 * [Element.enclosingElement] relation between patch/injected elements and the
 * patch library.
 *
 * For [ClassElement] and [FunctionElement] we use declarations for determining
 * identity and implementations for work based on the AST nodes, such as
 * resolution, type-checking, type inference, building SSA graphs, etc.
 * - Worklist only contain declaration elements.
 * - Most maps and sets use declarations exclusively, and their individual
 *   invariants are stated in the field comments.
 * - [tree.TreeElements] only map to patch elements from inside a patch library.
 *   TODO(johnniwinther): Simplify this invariant to use only declarations in
 *   [tree.TreeElements].
 * - Builders shift between declaration and implementation depending on usages.
 * - Compile-time constants use constructor implementation exclusively.
 * - Work on function parameters is performed on the declaration of the function
 *   element.
 */

library patchparser;

import 'dart:async';

import "dart2jslib.dart" as leg;  // CompilerTask, Compiler.
import "helpers/helpers.dart";
import "scanner/scannerlib.dart";  // Scanner, Parsers, Listeners
import "elements/elements.dart";
import "elements/modelx.dart"
    show LibraryElementX,
         MetadataAnnotationX,
         ClassElementX,
         FunctionElementX;
import "library_loader.dart" show LibraryLoader;
import 'util/util.dart';

class PatchParserTask extends leg.CompilerTask {
  PatchParserTask(leg.Compiler compiler): super(compiler);
  final String name = "Patching Parser";

  /**
   * Scans a library patch file, applies the method patches and
   * injections to the library, and returns a list of class
   * patches.
   */
  Future patchLibrary(LibraryLoader loader,
                      Uri patchUri, LibraryElement originLibrary) {
    return compiler.readScript(originLibrary, patchUri)
        .then((leg.Script script) {
      var patchLibrary = new LibraryElementX(script, null, originLibrary);
      return compiler.withCurrentElement(patchLibrary, () {
        loader.registerNewLibrary(patchLibrary);
        compiler.withCurrentElement(patchLibrary.entryCompilationUnit, () {
          // This patches the elements of the patch library into [library].
          // Injected elements are added directly under the compilation unit.
          // Patch elements are stored on the patched functions or classes.
          scanLibraryElements(patchLibrary.entryCompilationUnit);
        });
        return loader.processLibraryTags(patchLibrary);
      });
    });
  }

  void scanLibraryElements(CompilationUnitElement compilationUnit) {
    measure(() {
      // TODO(johnniwinther): Test that parts and exports are handled correctly.
      leg.Script script = compilationUnit.script;
      Token tokens = new Scanner(script.file).tokenize();
      Function idGenerator = compiler.getNextFreeClassId;
      Listener patchListener = new PatchElementListener(compiler,
                                                        compilationUnit,
                                                        idGenerator);
      new PartialParser(patchListener).parseUnit(tokens);
    });
  }

  void parsePatchClassNode(PartialClassElement element) {
    // Parse [PartialClassElement] using a "patch"-aware parser instead
    // of calling its [parseNode] method.
    if (element.cachedNode != null) return;

    measure(() => compiler.withCurrentElement(element, () {
      MemberListener listener = new MemberListener(compiler, element);
      Parser parser = new PatchClassElementParser(listener);
      Token token = parser.parseTopLevelDeclaration(element.beginToken);
      assert(identical(token, element.endToken.next));
      element.cachedNode = listener.popNode();
      assert(listener.nodes.isEmpty);

      Link<Element> patches = element.localMembers;
      applyContainerPatch(element.origin, patches);
    }));
  }

  void applyContainerPatch(ClassElement originClass,
                           Link<Element> patches) {
    for (Element patch in patches) {
      if (!isPatchElement(compiler, patch)) continue;

      Element origin = originClass.localLookup(patch.name);
      patchElement(compiler, origin, patch);
    }
  }
}

/**
 * Partial parser for patch files that also handles the members of class
 * declarations.
 */
class PatchClassElementParser extends PartialParser {
  PatchClassElementParser(Listener listener) : super(listener);

  Token parseClassBody(Token token) => fullParseClassBody(token);
}

/**
 * Extension of [ElementListener] for parsing patch files.
 */
class PatchElementListener extends ElementListener implements Listener {
  final leg.Compiler compiler;

  PatchElementListener(leg.Compiler compiler,
                       CompilationUnitElement patchElement,
                       int idGenerator())
    : this.compiler = compiler,
      super(compiler, patchElement, idGenerator);

  void pushElement(Element patch) {
    super.pushElement(patch);
    if (isPatchElement(compiler, patch)) {
      LibraryElement originLibrary = compilationUnitElement.library;
      assert(originLibrary.isPatched);
      Element origin = originLibrary.localLookup(patch.name);
      patchElement(listener, origin, patch);
    }
  }
}

void patchElement(leg.DiagnosticListener listener,
                  Element origin,
                  Element patch) {
  if (origin == null) {
    listener.reportError(
        patch, leg.MessageKind.PATCH_NON_EXISTING, {'name': patch.name});
    return;
  }
  if (!(origin.isClass ||
        origin.isConstructor ||
        origin.isFunction ||
        origin.isAbstractField)) {
    // TODO(ahe): Remove this error when the parser rejects all bad modifiers.
    listener.reportError(origin, leg.MessageKind.PATCH_NONPATCHABLE);
    return;
  }
  if (patch.isClass) {
    tryPatchClass(listener, origin, patch);
  } else if (patch.isGetter) {
    tryPatchGetter(listener, origin, patch);
  } else if (patch.isSetter) {
    tryPatchSetter(listener, origin, patch);
  } else if (patch.isConstructor) {
    tryPatchConstructor(listener, origin, patch);
  } else if(patch.isFunction) {
    tryPatchFunction(listener, origin, patch);
  } else {
    // TODO(ahe): Remove this error when the parser rejects all bad modifiers.
    listener.reportError(patch, leg.MessageKind.PATCH_NONPATCHABLE);
  }
}

void tryPatchClass(leg.DiagnosticListener listener,
                    Element origin,
                    ClassElement patch) {
  if (!origin.isClass) {
    listener.reportError(
        origin, leg.MessageKind.PATCH_NON_CLASS, {'className': patch.name});
    listener.reportInfo(
        patch, leg.MessageKind.PATCH_POINT_TO_CLASS, {'className': patch.name});
    return;
  }
  patchClass(listener, origin, patch);
}

void patchClass(leg.DiagnosticListener listener,
                ClassElementX origin,
                ClassElementX patch) {
  if (origin.isPatched) {
    listener.internalError(origin,
        "Patching the same class more than once.");
  }
  origin.applyPatch(patch);
}

void tryPatchGetter(leg.DiagnosticListener listener,
                    Element origin,
                    FunctionElement patch) {
  if (!origin.isAbstractField) {
    listener.reportError(
        origin, leg.MessageKind.PATCH_NON_GETTER, {'name': origin.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_GETTER, {'getterName': patch.name});
    return;
  }
  AbstractFieldElement originField = origin;
  if (originField.getter == null) {
    listener.reportError(
        origin, leg.MessageKind.PATCH_NO_GETTER, {'getterName': patch.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_GETTER, {'getterName': patch.name});
    return;
  }
  patchFunction(listener, originField.getter, patch);
}

void tryPatchSetter(leg.DiagnosticListener listener,
                     Element origin,
                     FunctionElement patch) {
  if (!origin.isAbstractField) {
    listener.reportError(
        origin, leg.MessageKind.PATCH_NON_SETTER, {'name': origin.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_SETTER, {'setterName': patch.name});
    return;
  }
  AbstractFieldElement originField = origin;
  if (originField.setter == null) {
    listener.reportError(
        origin, leg.MessageKind.PATCH_NO_SETTER, {'setterName': patch.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_SETTER, {'setterName': patch.name});
    return;
  }
  patchFunction(listener, originField.setter, patch);
}

void tryPatchConstructor(leg.DiagnosticListener listener,
                          Element origin,
                          FunctionElement patch) {
  if (!origin.isConstructor) {
    listener.reportError(
        origin,
        leg.MessageKind.PATCH_NON_CONSTRUCTOR, {'constructorName': patch.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_CONSTRUCTOR,
        {'constructorName': patch.name});
    return;
  }
  patchFunction(listener, origin, patch);
}

void tryPatchFunction(leg.DiagnosticListener listener,
                      Element origin,
                      FunctionElement patch) {
  if (!origin.isFunction) {
    listener.reportError(
        origin,
        leg.MessageKind.PATCH_NON_FUNCTION, {'functionName': patch.name});
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_FUNCTION, {'functionName': patch.name});
    return;
  }
  patchFunction(listener, origin, patch);
}

void patchFunction(leg.DiagnosticListener listener,
                   FunctionElementX origin,
                   FunctionElementX patch) {
  if (!origin.modifiers.isExternal) {
    listener.reportError(origin, leg.MessageKind.PATCH_NON_EXTERNAL);
    listener.reportInfo(
        patch,
        leg.MessageKind.PATCH_POINT_TO_FUNCTION, {'functionName': patch.name});
    return;
  }
  if (origin.isPatched) {
    listener.internalError(origin,
        "Trying to patch a function more than once.");
  }
  origin.applyPatch(patch);
}

// TODO(johnniwinther): Add unittest when patch is (real) metadata.
bool isPatchElement(leg.Compiler compiler, Element element) {
  // TODO(lrn): More checks needed if we introduce metadata for real.
  // In that case, it must have the identifier "native" as metadata.
  for (Link<MetadataAnnotation> link = element.metadata;
       !link.isEmpty;
       link = link.tail) {
    MetadataAnnotation annotation = link.head;
    if (annotation.beginToken != null &&
        annotation.beginToken.next.value == 'patch') {
      // TODO(johnniwinther): Perform this check in
      // [Compiler.onLibrariesLoaded].
      compiler.enqueuer.resolution.addDeferredAction(element, () {
        annotation.ensureResolved(compiler);
        if (annotation.value != compiler.patchConstant) {
          compiler.internalError(annotation, 'Invalid patch annotation.');
        }
      });
      return true;
    }
  }
  return false;
}
