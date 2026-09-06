local root = "SiKUIFramework/Contents/mods/SiKUIFramework/42/media/lua/client/"
package.path = root .. "?.lua;" .. package.path

UIFont = { Small = "small", Medium = "medium" }
local function derive(base) local out = {}; out.__index = out; setmetatable(out, base); return out end
local Base = {}; Base.__index = Base
local function nativeObject(owner)
        local native = {nativeOwner=owner, children={}}
        function native:AddChild(child)
                assert(self ~= child, "NATIVE_SELF_CHILD")
                local ancestor = self
                while ancestor do
                        assert(ancestor ~= child, "NATIVE_ANCESTOR_CYCLE")
                        ancestor = ancestor.parent
                end
                assert(child.parent == nil, "NATIVE_DUPLICATE_PARENT")
                self.children[#self.children+1] = child; child.parent = self
        end
        function native:RemoveChild(child)
                for i=#self.children,1,-1 do
                        if self.children[i] == child then table.remove(self.children,i) end
                end
                if child.parent == self then child.parent = nil end
        end
        return native
end
function Base:new(x, y, w, h) return setmetatable({ x=x or 0, y=y or 0, width=w or 0, height=h or 0, children={}, visible=true }, self) end
function Base:initialise() self.initialised = true; return self end
function Base:instantiate()
        self.instantiateCount=(self.instantiateCount or 0)+1
        self.javaObject=nativeObject(self); return self
end
function Base:addChild(child)
        -- Vanilla ISUIElement:addChild materializes BOTH peers before AddChild.
        if self.javaObject == nil then self:instantiate() end
        if child.javaObject == nil and child.instantiate then child:instantiate() end
        self.javaObject:AddChild(child.javaObject)
        child.parent = self; self.children[#self.children+1] = child
end
function Base:removeChild(child)
        if self.javaObject and child.javaObject then self.javaObject:RemoveChild(child.javaObject) end
        for i=#self.children,1,-1 do if self.children[i] == child then table.remove(self.children,i) end end
        if child.parent == self then child.parent=nil end
end
function Base:getParent() return self.parent end
function Base:setX(v) self.x=v end; function Base:setY(v) self.y=v end
function Base:setWidth(v) self.width=v end; function Base:setHeight(v) self.height=v end
function Base:getX() return self.x end; function Base:getY() return self.y end
function Base:getWidth() return self.width end; function Base:getHeight() return self.height end
function Base:setVisible(v) self.visible=v end; function Base:getIsVisible() return self.visible end
function Base:setMouseTransparent(v) self.mouseTransparent=v end
function Base:drawRect() end; function Base:drawRectBorder() end; function Base:prerender() end
function Base:dispose() if self.disposed then return false end; self.disposed=true; if self.parent then self.parent:removeChild(self) end; return true end

ISPanel = derive(Base)
ISLabel = derive(Base)
function ISLabel:new(x,y,h,text) local out=Base.new(self,x,y,0,h); out.name=text; return out end
ISTextEntryBox = derive(Base)
function ISTextEntryBox:new(text,x,y,w,h)
        local out=Base.new(self,x,y,w,h); out.text=text; return out
end
function ISTextEntryBox:instantiate()
        self.instantiateCount=(self.instantiateCount or 0)+1
        self.javaObject=nativeObject(self); return self
end
function ISTextEntryBox:getText() return self.text end
function ISTextEntryBox:setText(v) self.text=tostring(v or "") end
function ISTextEntryBox:setEditable(v) self.editable=v end
function ISTextEntryBox:setOnlyNumbers(v) self.onlyNumbers=v end
function ISTextEntryBox:setMaxTextLength(v) self.maxLength=v end
function ISTextEntryBox:setPlaceholderText(v) self.placeholder=v end
function ISTextEntryBox:focus() self.focused=true; return "focused" end
function ISTextEntryBox:selectAll() self.selected=true; return "selected" end
function ISTextEntryBox:setFont(v) self.font=v; return "font-set" end
function ISTextEntryBox:getInternalText() return self.text end
ISComboBox = derive(Base); function ISComboBox:new() return Base.new(self,0,0,1,1) end
function ISComboBox:addOptionWithData() end
package.preload["ISUI/ISPanel"] = function() return ISPanel end
package.preload["ISUI/ISLabel"] = function() return ISLabel end
package.preload["ISUI/ISTextEntryBox"] = function() return ISTextEntryBox end
package.preload["ISUI/ISComboBox"] = function() return ISComboBox end
function getTextManager() return { getFontHeight=function() return 18 end, MeasureStringX=function(_,_,v) return #tostring(v or "")*8 end } end
function getTexture(path) return {path=path} end; function getText(key) return key end

require "SiK/UI/Namespace"; require "SiK/UI/Theme"; require "SiK/UI/Metrics"
require "SiK/UI/Layout"; require "SiK/UI/Icon"; require "SiK/UI/Tooltip"; require "SiK/UI/Combo"
local Controls = require "SiK/UI/Controls"
local function eq(a,b,m) if a ~= b then error(m .. ": expected " .. tostring(b) .. ", got " .. tostring(a),2) end end
local function ok(v,m) if not v then error(m,2) end end

local host=ISPanel:new(0,0,500,300); host:initialise(); local changes,submits=0,0
local field=assert(Controls.field(host,{x=12,y=16,w=220,h=32,text="initial",textInset=10,numeric=true,maxLength=8,placeholder="Enter value",playerNum=1,
        onChange=function() changes=changes+1 end, onSubmit=function() submits=submits+1 end}))
local entry=assert(field.entry)
entry.target = { callbackOwner = entry }
eq(#host.children,1,"field attaches once to host"); eq(#field.children,1,"field has one native child")
eq(entry.parent,field,"native entry parent is field"); eq(entry:getParent(),field,"native entry exposes field parent")
ok(entry ~= field,"native entry is distinct"); ok(entry.javaObject ~= nil,"native entry is materialized")
ok(field.javaObject ~= nil,"field container is materialized")
ok(field.javaObject ~= entry.javaObject,"field does not alias native java identity")
ok(field.target ~= entry.target,"field does not alias optional callback target")
eq(entry.instantiateCount,1,"native entry materializes exactly once")
eq(field.instantiateCount,1,"field container materializes exactly once")
eq(#field.javaObject.children,1,"panel has exactly one native child")
eq(field.javaObject.children[1],entry.javaObject,"native child is entry")
eq(entry.javaObject.parent,field.javaObject,"native parent is panel")
eq(field.instantiate,Base.instantiate,"panel lifecycle is inherited, not forwarded")
-- Recreate the original opening operation, not just an isolated identity assert.
local legacy = ISPanel:new(0,0,100,30)
local legacyEntry = ISTextEntryBox:new("legacy",0,0,100,30); legacyEntry:instantiate()
legacy.javaObject = legacyEntry.javaObject
local caught, reason = pcall(function() legacy:addChild(legacyEntry) end)
eq(caught, false,"legacy opening with native alias is rejected")
ok(string.find(tostring(reason),"NATIVE_SELF_CHILD",1,true),"legacy opening reports regression marker")
field:setText("updated"); eq(field:getText(),"updated","text forwards")
field:setEnabled(false); eq(entry.editable,false,"disable forwards"); field:setEnabled(true); eq(entry.editable,true,"enable forwards")
field:setOnlyNumbers(false); eq(entry.onlyNumbers,false,"numeric forwards"); field:setMaxTextLength(5); eq(entry.maxLength,5,"length forwards")
field:setPlaceholderText("Hint"); eq(entry.placeholder,"Hint","placeholder forwards")
eq(field:focus(),"focused","focus forwards"); eq(field:selectAll(),"selected","selection forwards"); eq(field:setFont("medium"),"font-set","font forwards")
field:onTextChange(); field:onPressEnter(); eq(changes,1,"change callback once"); eq(submits,1,"submit callback once")
field:setBounds(20,24,260,44); eq(field.x,20,"field x reflows"); eq(field.y,24,"field y reflows"); eq(entry.x,10,"left inset preserved"); eq(entry.width,240,"native width follows padding"); eq(entry.height,44,"native height follows field")
local first=entry; ok(field:dispose(),"field disposes"); eq(field.entry,nil,"entry reference clears"); eq(first.parent,nil,"entry detaches"); eq(first.javaObject.parent,nil,"native entry detaches"); eq(#host.children,0,"field detaches"); eq(#host.javaObject.children,0,"native field detaches"); eq(field:dispose(),false,"dispose idempotent")
local reopened=assert(Controls.field(host,{text="reopened",w=180,h=30})); ok(reopened.entry ~= first,"reopen uses fresh native entry"); eq(reopened.entry.instantiateCount,1,"reopen materializes once"); eq(#host.children,1,"reopen does not duplicate host child"); ok(reopened:dispose(),"reopened field disposes")
return true
