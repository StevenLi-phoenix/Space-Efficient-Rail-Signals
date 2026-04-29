-- collision-mask-util still ships in Factorio 2.0 but with a trimmed API:
--   add_layer / remove_layer / mask_contains_layer were removed (use mask.layers[name] directly)
--   get_first_unused_layer was removed (layers must now be registered as prototypes)
local cmu = require("__core__.lualib.collision-mask-util")

-- Factorio 2.0: collision layers must be pre-declared as prototypes.
-- Docs recommend underscores over dashes in layer names.
local MAX_SIGNAL_LAYERS = 8
for i = 1, MAX_SIGNAL_LAYERS do
  data:extend({{ type = "collision-layer", name = "rail_signal_layer_" .. i }})
end

local next_layer_index = 1
local function get_next_signal_layer()
  if next_layer_index > MAX_SIGNAL_LAYERS then
    error("Space-Efficient-Rail-Signals: exceeded max signal layers (" .. MAX_SIGNAL_LAYERS .. ")")
  end
  local name = "rail_signal_layer_" .. next_layer_index
  next_layer_index = next_layer_index + 1
  return name
end

-- Factorio 2.0 rail entity types all extend RailPrototype (EntityWithOwnerPrototype).
-- Several other data.raw keys contain "rail" but are NOT physical rail entities:
--   rail-planner  → RailPlannerPrototype extends ItemPrototype   (item, no collision_mask)
--   rail-remnants → RailRemnantsPrototype extends CorpsePrototype (corpse, not a track)
--   rail-support  → RailSupportPrototype extends EntityWithOwnerPrototype (pillar, not RailPrototype)
-- Excluding these prevents cmu.get_mask from crashing on types absent from default_masks.
local NON_RAIL_ENTITY_TYPES = {
  ["rail-planner"]  = true,
  ["rail-remnants"] = true,
  ["rail-support"]  = true,
}

local function is_rail_type(type_name)
  return type_name:find("rail") ~= nil
    and type_name:find("signal") == nil
    and not NON_RAIL_ENTITY_TYPES[type_name]
end

local function get_rail_types()
  local result = {}
  for type_name in pairs(data.raw) do
    if is_rail_type(type_name) then
      result[type_name] = true
    end
  end
  return result
end

local rail_types = get_rail_types()
local colliding_signal_layers = {}  -- set: layer_name -> true

-- cmu.get_mask falls back to get_default_mask(entity.type) when collision_mask is nil.
-- get_default_mask errors on types absent from collision-mask-defaults (e.g. modded items).
-- This wrapper returns nil instead of throwing for unknown types.
local function safe_get_mask(entity)
  if entity.collision_mask then
    return entity.collision_mask
  end
  local ok, mask = pcall(cmu.get_mask, entity)
  return ok and mask or nil
end

-- Collect all layers that signals share with any rail type.
local function get_all_collisions()
  for _, signal_type in pairs({"rail-signal", "rail-chain-signal"}) do
    if not data.raw[signal_type] then goto continue_signal end
    for _, signal in pairs(data.raw[signal_type]) do
      local signal_mask = safe_get_mask(signal)
      if signal_mask and signal_mask.layers then
        for layer_name in pairs(signal_mask.layers) do
          for rail_type in pairs(rail_types) do
            if not data.raw[rail_type] then goto continue_rail_type end
            for _, rail in pairs(data.raw[rail_type]) do
              local rail_mask = safe_get_mask(rail)
              if rail_mask and rail_mask.layers and rail_mask.layers[layer_name] then
                colliding_signal_layers[layer_name] = true
              end
            end
            ::continue_rail_type::
          end
        end
      end
    end
    ::continue_signal::
  end
end

-- Back up every rail entity's collision_mask so we can restore it after editing.
-- cmu.get_mask() in 2.0 does NOT mutate the entity, but collect_prototypes_with_layer
-- iterates via default_masks which may miss some modded rail types. Explicit backup
-- guarantees rails are always restored regardless.
local rail_mask_backup = {}

local function backup_rails()
  for rail_type in pairs(rail_types) do
    if data.raw[rail_type] then
      rail_mask_backup[rail_type] = {}
      for name, entity in pairs(data.raw[rail_type]) do
        rail_mask_backup[rail_type][name] = table.deepcopy(entity.collision_mask)
      end
    end
  end
end

local function restore_rails()
  for rail_type, entities in pairs(rail_mask_backup) do
    for name, original_mask in pairs(entities) do
      if data.raw[rail_type] and data.raw[rail_type][name] then
        data.raw[rail_type][name].collision_mask = original_mask
      end
    end
  end
end

-- For each layer shared between signals and rails:
--   • Give every non-rail prototype that has that layer a new signal-only layer.
--   • For signals specifically, also remove the old shared layer.
-- Rails are skipped here and restored from backup afterward.
local function edit_non_rail_segment()
  for old_layer in pairs(colliding_signal_layers) do
    local new_layer = get_next_signal_layer()
    local prototypes = cmu.collect_prototypes_with_layer(old_layer)
    for _, prototype in pairs(prototypes) do
      if not rail_types[prototype.type] then
        -- Ensure the entity has an explicit collision_mask we can write to.
        -- cmu.get_mask returns entity.collision_mask OR a copy of the default.
        -- We must assign it back so the modification sticks.
        if not prototype.collision_mask then
          prototype.collision_mask = cmu.get_mask(prototype)
        end
        local mask = prototype.collision_mask
        mask.layers[new_layer] = true
        if prototype.type == "rail-signal" or prototype.type == "rail-chain-signal" then
          mask.layers[old_layer] = nil
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
        local mask1 = safe_get_mask(prototype1)
        local mask2 = safe_get_mask(prototype2)
        if mask1 and mask2 and not cmu.masks_collide(mask1, mask2) then
          log(tostring(prototype1.name) .. " did not collide with " .. tostring(prototype2.name))
          return false
        end
      end
    end
  end
  return true
end

local function all_prototypes_collide()
  local check_types = {"rail-signal", "rail-chain-signal"}
  for rail_type in pairs(rail_types) do
    table.insert(check_types, rail_type)
  end
  for _, prototype_type in pairs(check_types) do
    if prototypes_collide(prototype_type) == true then
      log("All " .. tostring(prototype_type) .. " collide")
    else
      log("Error: " .. tostring(prototype_type) .. " are not colliding. Attempting failsafe.")
      return false
    end
  end
  return true
end

-- Main execution
get_all_collisions()
backup_rails()
edit_non_rail_segment()
restore_rails()

if all_prototypes_collide() == false then
  -- Failsafe: a mod added signals that lost their shared layer. Add one shared
  -- signal layer to all signals so they still block each other.
  local shared_layer = get_next_signal_layer()
  for _, signal_type in pairs({"rail-signal", "rail-chain-signal"}) do
    if data.raw[signal_type] then
      for _, prototype in pairs(data.raw[signal_type]) do
        if not prototype.collision_mask then
          prototype.collision_mask = cmu.get_mask(prototype)
        end
        prototype.collision_mask.layers[shared_layer] = true
      end
    end
  end
end

all_prototypes_collide()
