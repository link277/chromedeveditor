Polymer("core-selector",{selected:null,multi:false,valueattr:"name",selectedClass:"core-selected",selectedProperty:"",selectedAttribute:"active",selectedItem:null,selectedModel:null,selectedIndex:-1,target:null,itemsSelector:"",activateEvent:"tap",notap:false,ready:function(){this.activateListener=this.activateHandler.bind(this);this.observer=new MutationObserver(this.updateSelected.bind(this));if(!this.target){this.target=this}},get items(){if(!this.target){return[]}var nodes=this.target!==this?this.itemsSelector?this.target.querySelectorAll(this.itemsSelector):this.target.children:this.$.items.getDistributedNodes();return Array.prototype.filter.call(nodes||[],function(n){return n&&n.localName!=="template"})},targetChanged:function(old){if(old){this.removeListener(old);this.observer.disconnect();this.clearSelection()}if(this.target){this.addListener(this.target);this.observer.observe(this.target,{childList:true});this.updateSelected()}},addListener:function(node){Polymer.addEventListener(node,this.activateEvent,this.activateListener)},removeListener:function(node){Polymer.removeEventListener(node,this.activateEvent,this.activateListener)},get selection(){return this.$.selection.getSelection()},selectedChanged:function(){this.updateSelected()},updateSelected:function(){this.validateSelected();if(this.multi){this.clearSelection();this.selected&&this.selected.forEach(function(s){this.valueToSelection(s)},this)}else{this.valueToSelection(this.selected)}},validateSelected:function(){if(this.multi&&!Array.isArray(this.selected)&&this.selected!==null&&this.selected!==undefined){this.selected=[this.selected]}},clearSelection:function(){if(this.multi){this.selection.slice().forEach(function(s){this.$.selection.setItemSelected(s,false)},this)}else{this.$.selection.setItemSelected(this.selection,false)}this.selectedItem=null;this.$.selection.clear()},valueToSelection:function(value){var item=value===null||value===undefined?null:this.items[this.valueToIndex(value)];this.$.selection.select(item)},updateSelectedItem:function(){this.selectedItem=this.selection},selectedItemChanged:function(){if(this.selectedItem){var t=this.selectedItem.templateInstance;this.selectedModel=t?t.model:undefined}else{this.selectedModel=null}this.selectedIndex=this.selectedItem?parseInt(this.valueToIndex(this.selected)):-1},valueToIndex:function(value){for(var i=0,items=this.items,c;c=items[i];i++){if(this.valueForNode(c)==value){return i}}return value},valueForNode:function(node){return node[this.valueattr]||node.getAttribute(this.valueattr)},selectionSelect:function(e,detail){this.updateSelectedItem();if(detail.item){this.applySelection(detail.item,detail.isSelected)}},applySelection:function(item,isSelected){if(this.selectedClass){item.classList.toggle(this.selectedClass,isSelected)}if(this.selectedProperty){item[this.selectedProperty]=isSelected}if(this.selectedAttribute&&item.setAttribute){if(isSelected){item.setAttribute(this.selectedAttribute,"")}else{item.removeAttribute(this.selectedAttribute)}}},activateHandler:function(e){if(!this.notap){var i=this.findDistributedTarget(e.target,this.items);if(i>=0){var item=this.items[i];var s=this.valueForNode(item)||i;if(this.multi){if(this.selected){this.addRemoveSelected(s)}else{this.selected=[s]}}else{this.selected=s}this.asyncFire("core-activate",{item:item})}}},addRemoveSelected:function(value){var i=this.selected.indexOf(value);if(i>=0){this.selected.splice(i,1)}else{this.selected.push(value)}this.valueToSelection(value)},findDistributedTarget:function(target,nodes){while(target&&target!=this){var i=Array.prototype.indexOf.call(nodes,target);if(i>=0){return i}target=target.parentNode}},selectIndex:function(index){var item=this.items[index];if(item){this.selected=this.valueForNode(item)||index}},selectPrevious:function(){this.selectIndex(this.selectedIndex-1)},selectNext:function(){this.selectIndex(this.selectedIndex+1)}});