-- Register custom collision layers required by Factorio 2.0
-- Layers must be declared as prototypes before use in collision masks
local MAX_SIGNAL_LAYERS = 6
for i = 1, MAX_SIGNAL_LAYERS do
  data:extend({{ type = "collision-layer", name = "rail-signal-layer-" .. i }})
end

local colliding_signal_layers = {} -- set of rail signal layers that collide with rail-segments
local copy_of_rails = {}
local next_layer_index = 1

-- Inline collision utilities compatible with Factorio 2.0's named-layer format.
-- Factorio 2.0 uses { layers = { ["layer-name"] = true } } instead of numeric indices.
local cu = {}

function cu.get_mask(entity)
  if not entity.collision_mask then
    entity.collision_mask = { layers = {} }
  elseif not entity.collision_mask.layers then
    entity.collision_mask.layers = {}
  end
  return entity.collision_mask
end

function cu.mask_contains_layer(mask, layer_name)
  return mask.layers ~= nil and mask.layers[layer_name] == true
end

function cu.add_layer(mask, layer_name)
  if not mask.layers then mask.layers = {} end
  mask.layers[layer_name] = true
end

function cu.remove_layer(mask, layer_name)
  if mask.layers then
    mask.layers[layer_name] = nil
  end
end

function cu.masks_collide(mask1, mask2)
  if not mask1.layers or not mask2.layers then return false end
  for layer_name in pairs(mask1.layers) do
    if mask2.layers[layer_name] then
      return true
    end
  end
  return false
end

function cu.collect_prototypes_with_layer(layer_name)
  local result = {}
  for _, type_data in pairs(data.raw) do
    if type(type_data) == "table" then
      for _, prototype in pairs(type_data) do
        if type(prototype) == "table"
          and prototype.collision_mask
          and prototype.collision_mask.layers
          and prototype.collision_mask.layers[layer_name] then
          table.insert(result, prototype)
        end
      end
    end
  end
  return result
end

function cu.get_next_signal_layer()
  if next_layer_index > MAX_SIGNAL_LAYERS then
    error("Space-Efficient-Rail-Signals: exceeded max signal layers (" .. MAX_SIGNAL_LAYERS .. ")")
  end
  local name = "rail-signal-layer-" .. next_layer_index
  next_layer_index = next_layer_index + 1
  return name
end

-- Copies straight-rail and curved-rail segments between tables (overwrites destination).
local function copy_all_rails(old, new)
  for _, rail_type in pairs({"straight-rail", "curved-rail"}) do
    if old[rail_type] then
      new[rail_type] = table.deepcopy(old[rail_type])
    end
  end
end

local function get_collisions(signal_type, rail_type)
  if not data.raw[signal_type] or not data.raw[rail_type] then return end
  for _, signal in pairs(data.raw[signal_type]) do
    local signal_mask = cu.get_mask(signal)
    if signal_mask.layers then
      for layer_name in pairs(signal_mask.layers) do
        for _, rail in pairs(data.raw[rail_type]) do
          local rail_mask = cu.get_mask(rail)
          if cu.mask_contains_layer(rail_mask, layer_name) then
            colliding_signal_layers[layer_name] = true
          end
        end
      end
    end
  end
end

local function get_all_collisions()
  for _, signal_type in pairs({"rail-signal", "rail-chain-signal"}) do
    for _, rail_type in pairs({"straight-rail", "curved-rail"}) do
      get_collisions(signal_type, rail_type)
    end
  end
end

-- For each layer shared by signals and rails, create a new signal-only layer so that
-- signals no longer share collision layers with rails and can be placed freely.
local function edit_non_rail_segment()
  for old_layer, _ in pairs(colliding_signal_layers) do
    local new_layer = cu.get_next_signal_layer()
    local prototypes = cu.collect_prototypes_with_layer(old_layer)
    for _, prototype in pairs(prototypes) do
      local prototype_mask = cu.get_mask(prototype)
      if prototype.type ~= "straight-rail" and prototype.type ~= "curved-rail" then
        if cu.mask_contains_layer(prototype_mask, old_layer) then
          cu.add_layer(prototype_mask, new_layer)
          if prototype.type == "rail-signal" or prototype.type == "rail-chain-signal" then
            cu.remove_layer(prototype_mask, old_layer)
          end
        end
      end
    end
  end
end

local function prototypes_collide(prototype_type)
  if not data.raw[prototype_type] then return true end
  for _, prototype1 in pairs(data.raw[prototype_type]) do
    for _, prototype2 in pairs(data.raw[prototype_type]) do
      if prototype1 ~= prototype2 then
        local mask1 = cu.get_mask(prototype1)
        local mask2 = cu.get_mask(prototype2)
        if not cu.masks_collide(mask1, mask2) then
          log(tostring(prototype1.name) .. " did not collide with " .. tostring(prototype2.name))
          return false
        end
      end
    end
  end
  return true
end

local function all_prototypes_collide()
  for _, prototype_type in pairs({"straight-rail", "curved-rail", "rail-signal", "rail-chain-signal"}) do
    if prototypes_collide(prototype_type) == true then
      log("All " .. tostring(prototype_type) .. " collide")
    else
      log("Error: " .. tostring(prototype_type) .. " are not colliding. Attempting failsafe.")
      return false
    end
  end
  return true
end

get_all_collisions()
copy_all_rails(data.raw, copy_of_rails)
edit_non_rail_segment()
copy_all_rails(copy_of_rails, data.raw)

if all_prototypes_collide() == false then
  -- Failsafe: some mod added signals that don't share any layer after edits.
  -- Add one shared layer to all signals so they still collide with each other.
  local shared_collision_layer = cu.get_next_signal_layer()
  for _, prototype_type in pairs({"rail-signal", "rail-chain-signal"}) do
    if data.raw[prototype_type] then
      for _, prototype in pairs(data.raw[prototype_type]) do
        local collision_mask = cu.get_mask(prototype)
        cu.add_layer(collision_mask, shared_collision_layer)
      end
    end
  end
end

all_prototypes_collide()
