require "SiK/UI/Namespace"

SiK = SiK or {}
SiK.UI = SiK.UI or {}

local OrderedBlocks = SiK.UI.OrderedBlocks or {}
SiK.UI.Namespace.define("OrderedBlocks", OrderedBlocks)

local function height(node)
	return node and node.height or 0
end

local function rootCount(node)
	return node and node.count or 0
end

local function projectionCount(node)
	return node and node.projectedCount or 0
end

local function entryWeight(entry)
	return type(entry) == "table" and type(entry.block) == "table" and #entry.block or 0
end

local function makeNode(entry, left, right)
	return {
		entry = entry,
		left = left,
		right = right,
		height = 1 + math.max(height(left), height(right)),
		count = 1 + rootCount(left) + rootCount(right),
		projectedCount = entryWeight(entry) + projectionCount(left) + projectionCount(right),
	}
end

local function rotateLeft(root)
	local pivot = root.right
	local moved = makeNode(root.entry, root.left, pivot.left)
	return makeNode(pivot.entry, moved, pivot.right)
end

local function rotateRight(root)
	local pivot = root.left
	local moved = makeNode(root.entry, pivot.right, root.right)
	return makeNode(pivot.entry, pivot.left, moved)
end

local function balance(root)
	local delta = height(root.left) - height(root.right)
	if delta > 1 then
		if height(root.left.left) < height(root.left.right) then
			return rotateRight(makeNode(root.entry, rotateLeft(root.left), root.right))
		end
		return rotateRight(root)
	elseif delta < -1 then
		if height(root.right.right) < height(root.right.left) then
			return rotateLeft(makeNode(root.entry, root.left, rotateRight(root.right)))
		end
		return rotateLeft(root)
	end
	return root
end

function OrderedBlocks.insert(root, entry, less)
	if not root then return makeNode(entry, nil, nil) end
	if less(entry, root.entry) then
		return balance(makeNode(root.entry, OrderedBlocks.insert(root.left, entry, less), root.right))
	elseif less(root.entry, entry) then
		return balance(makeNode(root.entry, root.left, OrderedBlocks.insert(root.right, entry, less)))
	end
	if root.entry == entry then return root end
	return makeNode(entry, root.left, root.right)
end

local function minimum(root)
	while root.left do root = root.left end
	return root
end

function OrderedBlocks.remove(root, entry, less)
	if not root then return nil end
	if less(entry, root.entry) then
		local left = OrderedBlocks.remove(root.left, entry, less)
		if left == root.left then return root end
		return balance(makeNode(root.entry, left, root.right))
	elseif less(root.entry, entry) then
		local right = OrderedBlocks.remove(root.right, entry, less)
		if right == root.right then return root end
		return balance(makeNode(root.entry, root.left, right))
	end
	if not root.left then return root.right end
	if not root.right then return root.left end
	local successor = minimum(root.right)
	return balance(makeNode(successor.entry, root.left,
		OrderedBlocks.remove(root.right, successor.entry, less)))
end

function OrderedBlocks.at(root, index)
	if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil end
	while root do
		local leftCount = rootCount(root.left)
		if index == leftCount + 1 then return root.entry end
		if index <= leftCount then
			root = root.left
		else
			index = index - leftCount - 1
			root = root.right
		end
	end
	return nil
end

function OrderedBlocks.projectedAt(root, index)
	if type(index) ~= "number" or index < 1 or index ~= math.floor(index) then return nil end
	local skippedRoots = 0
	while root do
		local leftProjected = projectionCount(root.left)
		local leftRoots = rootCount(root.left)
		local weight = entryWeight(root.entry)
		if index <= leftProjected then
			root = root.left
		elseif index <= leftProjected + weight then
			local offset = index - leftProjected
			return root.entry.block[offset], skippedRoots + leftRoots + 1, root.entry, offset
		else
			index = index - leftProjected - weight
			skippedRoots = skippedRoots + leftRoots + 1
			root = root.right
		end
	end
	return nil
end

function OrderedBlocks.rank(root, entry, less)
	local skipped = 0
	while root do
		if less(entry, root.entry) then
			root = root.left
		elseif less(root.entry, entry) then
			skipped = skipped + rootCount(root.left) + 1
			root = root.right
		else
			return skipped + rootCount(root.left) + 1
		end
	end
	return nil
end

function OrderedBlocks.count(root)
	return rootCount(root)
end

function OrderedBlocks.projectedCount(root)
	return projectionCount(root)
end

return OrderedBlocks
