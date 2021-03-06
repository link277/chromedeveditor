part of ace.proxy;

js.JsObject get _ace => _context['ace'];
js.JsObject get _context => js.context;
js.JsObject get _modules => _ace['define']['modules'];
final js.JsFunction _Object = _context['Object'];

js.JsObject _jsArray(list) => new js.JsArray.from(list);

js.JsObject _jsObject() => new js.JsObject(_Object);

js.JsObject _jsMap(map) {
  final jsMap = new js.JsObject(_Object);
  map.forEach((k, v) {
    jsMap[k] = v;
  });
  return jsMap;
}

js.JsObject _jsify(obj) => new js.JsObject.jsify(obj);

js.JsObject _jsAnnotation(Annotation a) => _jsMap({
  'html': a.html, 
  'row' : a.row,
  'text': a.text,
  'type': a.type
});

js.JsObject _jsBindKey(BindKey bk) => _jsMap({
  'win' : bk.win,
  'mac' : bk.mac
});

js.JsObject _jsCompletion(Completion c) {
  final jsMap = _jsMap({
    'value' : c.value
  });
  if (c.snippet != null) {
    jsMap['snippet'] = c.snippet;
  }
  if (c.score != null) {
    jsMap['score'] = c.score;
  }
  if (c.meta != null) {
    jsMap['meta'] = c.meta;
  }
  return jsMap;
}

js.JsObject _jsDelta(d) {
  final jsMap = _jsMap({ 'action': d.action, 'range': _jsRange(d.range) });
  if (d.action == Delta.INSERT_LINES || d.action == Delta.REMOVE_LINES) {
    jsMap['lines'] = _jsArray(d.lines);
  }
  if (d.action == Delta.INSERT_TEXT || d.action == Delta.REMOVE_TEXT) {
    jsMap['text'] = d.text;
  }
  if (d.action == Delta.REMOVE_LINES) {
    jsMap['nl'] = d.nl;
  }
  return jsMap;
}

js.JsObject _jsMarker(Marker m) => _jsMap({
  'clazz'   : m.className,
  'id'      : m.id,
  'inFront' : m.inFront,
  'range'   : m.range == null ? null : _jsRange(m.range),
  'type'    : m.type
});

js.JsObject _jsPoint(Point p) =>  _jsMap({ 'row': p.row, 'column': p.column });

js.JsObject _jsRange(Range r) => new js.JsObject(_modules['ace/range']['Range'], 
    [r.start.row, r.start.column, r.end.row, r.end.column]);

js.JsObject _jsSearchOptions(SearchOptions so) => _jsMap({
  'backwards'     : so.backwards,
  'caseSensitive' : so.caseSensitive,
  'needle'        : so.needle,
  'range'         : so.range == null ? null : _jsRange(so.range),
  'regExp'        : so.regExp,
  'skipCurrent'   : so.skipCurrent,
  'start'         : so.start == null ? null : _jsRange(so.start),
  'wholeWord'     : so.wholeWord,
  'wrap'          : so.wrap 
});

List _list(js.JsObject array) => JSON.decode(_stringify(array));

Map _map(js.JsObject obj) => JSON.decode(_stringify(obj));

String _stringify(js.JsObject obj) => 
    _context['JSON'].callMethod('stringify', [obj]);

Annotation _annotation(proxy) => new Annotation(
    html: proxy['html'],
    row : proxy['row'] == null ? 0 : proxy['row'],
    text: proxy['text'],
    type: proxy['type'] == null ? Annotation.INFO : proxy['type']);

BindKey _bindKey(proxy) => new BindKey(mac: proxy['mac'], win: proxy['win']);

Delta _delta(proxy) => new Delta(proxy['action'], _range(proxy['range']), 
      lines: proxy['lines'] == null ? null : _list(proxy['lines']), 
      nl: proxy['nl'], text: proxy['text']);

LinkEvent _linkEvent(proxy) {
  final t = proxy['token'];
  final position = _point(proxy['position']);
  final token = (t == null) ? null : _token(t);
  return new LinkEvent(position, token);
}

Marker _marker(proxy) => new Marker(
    range     : proxy['range'] == null ? null : _range(proxy['range']),
    className : proxy['clazz'],
    id        : proxy['id'],
    inFront   : proxy['inFront'],
    type      : proxy['type']);

Point _point(proxy) => new Point(proxy['row'], proxy['column']);

Range _range(proxy) => new Range(
    proxy['start']['row'], 
    proxy['start']['column'], 
    proxy['end']['row'], 
    proxy['end']['column']);

SearchOptions _searchOptions(proxy) => new SearchOptions(
    backwards: proxy['backwards'] == null ? false : proxy['backwards'],
    caseSensitive: proxy['caseSensitive'] == null ? false 
        : proxy['caseSensitive'],
    needle: proxy['needle'] == null ? '' : proxy['needle'],
    range: proxy['range'] == null ? null : _range(proxy['range']),
    regExp: proxy['regExp'] == null ? false : proxy['regExp'],
    skipCurrent: proxy['skipCurrent'] == null ? false : proxy['skipCurrent'],
    start: proxy['start'] == null ? null : _range(proxy['start']),
    wholeWord: proxy['wholeWord'] == null ? false : proxy['wholeWord'],
    wrap: proxy['wrap'] == null ? false : proxy['wrap']);

Token _token(proxy) => new Token(
    type:  proxy['type'],
    value: proxy['value'],
    index: proxy['index'] == null ? null : proxy['index'],
    start: proxy['start'] == null ? null : proxy['start']);

UndoManagerDelta _undoManagerDelta(proxy) => new UndoManagerDelta(
    proxy['group'],
    proxy['deltas'].map(_delta).toList(growable: false));

abstract class HasProxy extends Disposable {
  
  js.JsObject _proxy;
  
  final Future _onHasProxy;
  
  bool get _hasProxy => _proxy != null;
  
  // We don't expose `proxy` as it is easily shadowed by `dart:core`.
  js.JsObject get jsProxy => _proxy;
  
  HasProxy.async(Future<js.JsObject> getProxy) : _onHasProxy = getProxy {
    getProxy.then((proxy) => _proxy = proxy);
  }
  
  HasProxy(js.JsObject proxy) 
  : _proxy = proxy
  , _onHasProxy = null;
  
  call(String name, [List args]) => _proxy.callMethod(name, args);
      
  Future dispose() {
    if (!_hasProxy) return new Future.value();
    return _onDispose().whenComplete(() {
      _proxy = null;
    });
  }
  
  Future _onDispose() => new Future.value();
}

class _Event<T> extends Disposable {
  
  final HasProxy _proxy;
  final String _name;
  final Function _onEvent;
    
  StreamController<T> _s;
  js.JsFunction _cb;
  
  Stream<T> get stream {
    if (_s == null) {
      _s = new StreamController<T>.broadcast(
        onListen: () {
          _cb = _proxy.call('addEventListener', [_name, (e,__) {
            _s.add(_onEvent == null ? null : _onEvent(e));
          }]);
        },
        onCancel: () {
          _proxy.call('removeEventListener', [_name, _cb]);
          _cb = null;
        }
      );
    }
    return _s.stream;
  }
  
  _Event(this._proxy, this._name, [this._onEvent(event)]);
  
  Future dispose() {
    if (_s == null) return new Future.value();
    return _s.close();
  }
}
