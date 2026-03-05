#!/bin/bash
# =============================================================================
# Motherlode Sprite Generator - PixelLab API
# =============================================================================
# Generates all hull and drill sprites for 6 upgrade tiers with full animations.
#
# ~82 API calls producing 250+ sprite frames:
#   - 6 hull tiers × (1 base + 8 idle + 8 thrust + 4 left + 4 right + 4 drill + 4 damage + 4 critical) = 48
#   - 6 drill tiers × (1 base + 8 spin + 4 impact) = 18
#   - 16 shared effect calls (base+animate pairs for 7 effects + 2 static) = 16
#
# Usage:
#   bash tool/generate_sprites.sh          # Generate everything
#   bash tool/generate_sprites.sh hull 0   # Generate only hull tier 0
#   bash tool/generate_sprites.sh drill 3  # Generate only drill tier 3
#   bash tool/generate_sprites.sh effects  # Generate only shared effects
#
# Requires: curl, jq, base64 (Git Bash on Windows has all of these)
# =============================================================================

set -uo pipefail

# Ensure ~/bin and mingw64 are on PATH (for locally installed jq, curl)
export PATH="$HOME/bin:/mingw64/bin:$PATH"

API_KEY="0cc783ce-fa16-4045-9f36-daeb386a6931"
API_BASE="https://api.pixellab.ai/v1"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${PROJ_DIR}/assets/images"
STYLE_REF="${PROJ_DIR}/assets/images/pod/mining_hull.png"

# ---------------------------------------------------------------------------
# Quality settings - maximized for detail
# ---------------------------------------------------------------------------
OUTLINE="selective outline"
SHADING="highly detailed shading"
DETAIL="highly detailed"
VIEW="side"
DIRECTION="south"
TEXT_GUIDE=12          # High text adherence
IMG_GUIDE=4.0          # Very strong reference adherence — keeps character consistent
STYLE_STRENGTH=35      # How much existing hull style bleeds through

# ---------------------------------------------------------------------------
# Tier definitions
# ---------------------------------------------------------------------------
# Each tier: (name, hull_prompt, drill_prompt, accent_hex)

TIER_NAMES=("prospector" "ironclad" "vulcan" "frostbite" "inferno" "motherlode")

HULL_PROMPTS=(
  # Tier 0 - Prospector
  "worn rugged mining pod, dark green-gray painted metal hull with rust patches and dents, basic round cockpit viewport with orange glow, two small cylindrical side-mounted engines, exposed rivets and welded seams, industrial utilitarian design, front-facing symmetric, pixel art game character sprite"

  # Tier 1 - Ironclad
  "reinforced mining pod, polished steel hull with bolt-on armor plates, hexagonal viewport with cyan HUD glow, upgraded twin engines with chrome exhausts, reinforcement struts visible, military-grade construction, front-facing symmetric, pixel art game character sprite"

  # Tier 2 - Vulcan
  "heavy industrial mining pod, thick burnt-orange and dark brown layered armor plating, wide reinforced viewport with amber scanner beam, large dual exhaust stacks with heat vents, hazard warning stripes on shoulders, heavy-duty hydraulic joints visible, front-facing symmetric, pixel art game character sprite"

  # Tier 3 - Frostbite
  "sleek advanced mining pod, polished titanium-blue hull with clean aerodynamic curves, narrow slit viewport with bright blue holographic display, integrated streamlined engines with blue LED accent strips running along hull edges, advanced tech panels with circuitry lines, front-facing symmetric, pixel art game character sprite"

  # Tier 4 - Inferno
  "aggressive quantum mining pod, dark crimson angular hull with visible glowing orange magma core reactor through ventilation slits, sharp geometric viewport with red targeting reticle, powerful engines with orange energy exhaust ports, heat shimmer distortion lines, molten cracks of light across armor surface, front-facing symmetric, pixel art game character sprite"

  # Tier 5 - Motherlode
  "legendary crystalline mining pod, shimmering diamond-encrusted golden hull with prismatic light reflections, ornate viewport with radiant white-gold glow, magnificent engines with trailing golden particle exhaust, ethereal energy shield aura surrounding the hull, masterwork engravings on every surface, crown-like antenna array on top, front-facing symmetric, pixel art game character sprite"
)

DRILL_PROMPTS=(
  # Tier 0
  "basic gray steel drill bit, simple industrial auger with spiral grooves, worn metal with scratches, functional tool, vertical orientation pointing down, pixel art game item sprite"

  # Tier 1
  "polished silver drill bit, refined double-helix spiral, chrome finish with blue tint reflections, improved engineering, vertical pointing down, pixel art game item sprite"

  # Tier 2
  "gold-plated heavy auger drill, thick reinforced golden spiral with gear mechanism at base, industrial power tool, warm metallic sheen, vertical pointing down, pixel art game item sprite"

  # Tier 3
  "emerald crystal drill head, translucent green gemstone tip with titanium mounting bracket, energy lines flowing through crystal, elegant precision tool, vertical pointing down, pixel art game item sprite"

  # Tier 4
  "magma-infused drill, dark metal drill with glowing orange-red molten veins pulsing through it, heat waves radiating from tip, volcanic energy tool, vertical pointing down, pixel art game item sprite"

  # Tier 5
  "legendary diamond spiral drill, massive prismatic crystal drill head refracting rainbow light, golden filigree mounting, ethereal glow emanating from core, ultimate excavation tool, vertical pointing down, pixel art game item sprite"
)

# Short stable descriptions for animate calls — keeps the model anchored to the reference
HULL_ANIM_DESC=(
  "green mining pod with orange cockpit, pixel art sprite"
  "steel armored mining pod with cyan viewport, pixel art sprite"
  "orange industrial mining pod with amber viewport, pixel art sprite"
  "blue titanium mining pod with blue viewport, pixel art sprite"
  "crimson mining pod with glowing orange core, pixel art sprite"
  "golden crystalline mining pod with white glow, pixel art sprite"
)

DRILL_ANIM_DESC=(
  "gray steel drill bit, pixel art sprite"
  "silver chrome drill bit, pixel art sprite"
  "gold plated drill bit, pixel art sprite"
  "green crystal drill head, pixel art sprite"
  "dark drill with glowing orange veins, pixel art sprite"
  "diamond prismatic drill head, pixel art sprite"
)

NEG_HULL="drill, drill bit, weapon below, legs, arms, text, letters, watermark, blurry, low quality, deformed, background scenery"
NEG_DRILL="vehicle, pod, hull, body, cockpit, engine, text, letters, watermark, blurry, low quality, background scenery"

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------
call_count=0
fail_count=0

log() { echo "[$(date +%H:%M:%S)] $*"; }

# Pre-flight checks
for cmd in curl jq base64; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '${cmd}' is required but not found in PATH."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# API call with retry on rate limit
# ---------------------------------------------------------------------------
api_call() {
  local endpoint="$1"
  local body="$2"
  local output="$3"
  local multi="${4:-single}"
  local max_retries=3

  call_count=$((call_count + 1))
  log "#${call_count} POST /${endpoint} -> $(basename "$output")"

  # Write body to temp file to avoid shell quoting / CRLF issues
  local tmpfile
  tmpfile=$(mktemp)
  echo "$body" | tr -d '\r' > "$tmpfile"

  for attempt in $(seq 1 $max_retries); do
    local response
    response=$(curl -s -w "\n%{http_code}" \
      "${API_BASE}/${endpoint}" \
      --request POST \
      --header 'Content-Type: application/json' \
      --header "Authorization: Bearer ${API_KEY}" \
      --max-time 120 \
      --data @"$tmpfile" 2>&1) || true

    local http_code
    http_code=$(echo "$response" | tail -1)
    local json_body
    json_body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
      local cost
      cost=$(echo "$json_body" | jq -r '.usage.usd // 0' 2>/dev/null || echo "?")
      log "  OK (\$${cost})"

      if [[ "$multi" == "multi" ]]; then
        local count
        count=$(echo "$json_body" | jq '.images | length' 2>/dev/null || echo 0)
        for ((i=0; i<count; i++)); do
          echo "$json_body" | jq -r ".images[$i].base64" | base64 -d > "${output}_${i}.png"
        done
        log "  Saved ${count} frames"
      else
        echo "$json_body" | jq -r '.image.base64' | base64 -d > "${output}.png"
        log "  Saved 1 image"
      fi
      rm -f "$tmpfile"
      return 0
    elif [[ "$http_code" == "429" || "$http_code" == "529" ]]; then
      log "  Rate limited (${http_code}), waiting 10s... (attempt ${attempt}/${max_retries})"
      sleep 10
    else
      log "  ERROR: HTTP ${http_code}"
      log "  ${json_body:0:200}"
      rm -f "$tmpfile"
      fail_count=$((fail_count + 1))
      return 0  # Log and continue
    fi
  done

  rm -f "$tmpfile"
  log "  FAILED after ${max_retries} retries"
  fail_count=$((fail_count + 1))
  return 0  # Don't abort script on failure; fail_count tracks issues
}

# Base64 encode an image file for API
img_b64() {
  local b64
  b64=$(base64 -w 0 "$1" 2>/dev/null || base64 "$1" 2>/dev/null)
  echo "{\"type\":\"base64\",\"base64\":\"${b64}\"}"
}

# Short pause between calls to be respectful of rate limits
pace() { sleep 1; }

# ---------------------------------------------------------------------------
# Hull generation for one tier
# ---------------------------------------------------------------------------
generate_hull() {
  local tier=$1
  local name="${TIER_NAMES[$tier]}"
  local prompt="${HULL_PROMPTS[$tier]}"
  local dir="${OUT_DIR}/pod/hull_${tier}"
  mkdir -p "$dir"

  log "====== HULL TIER ${tier}: ${name} ======"

  # --- Base sprite (pixflux at 64x64 — must match animate-with-text output size) ---
  api_call "generate-image-pixflux" "$(cat <<ENDJSON
{
  "description": "${prompt}",
  "negative_description": "${NEG_HULL}",
  "image_size": {"width": 64, "height": 64},
  "text_guidance_scale": ${TEXT_GUIDE},
  "outline": "${OUTLINE}",
  "shading": "${SHADING}",
  "detail": "${DETAIL}",
  "view": "${VIEW}",
  "direction": "${DIRECTION}",
  "no_background": true,
  "seed": $((tier * 10000 + 2))
}
ENDJSON
)" "${dir}/base"
  pace

  # Pick the base for animation reference
  local ref_file="${dir}/base.png"
  [[ ! -f "$ref_file" ]] && { log "SKIP: No base hull generated for tier ${tier}"; return 0; }
  local ref_json
  ref_json=$(img_b64 "$ref_file")

  # Short description anchors animations to reference image
  local anim_desc="${HULL_ANIM_DESC[$tier]}"

  # Helper for hull animation calls — high image guidance, low text guidance
  _hull_anim() {
    local anim_name="$1" action="$2" frames="$3" seed_offset="$4"
    api_call "animate-with-text" "$(cat <<ENDJSON
{
  "description": "${anim_desc}",
  "negative_description": "${NEG_HULL}",
  "action": "${action}",
  "image_size": {"width": 64, "height": 64},
  "text_guidance_scale": 5,
  "image_guidance_scale": ${IMG_GUIDE},
  "n_frames": ${frames},
  "view": "${VIEW}",
  "direction": "${DIRECTION}",
  "reference_image": ${ref_json},
  "seed": $((tier * 10000 + seed_offset))
}
ENDJSON
)" "${dir}/${anim_name}" "multi"
    pace
  }

  _hull_anim "idle"       "subtle engine glow pulsing"                              8 1000
  _hull_anim "thrust"     "engines firing with bright exhaust flames below"          8 2000
  _hull_anim "move_left"  "tilting slightly left"                                    4 3000
  _hull_anim "move_right" "tilting slightly right"                                   4 4000
  _hull_anim "drilling"   "vibrating with dust rising"                               4 5000
  _hull_anim "damage"     "bright spark flash on hull"                               4 6000
  _hull_anim "critical"   "smoking with sparks and cracked hull"                     4 7000

  log "Hull tier ${tier} (${name}) complete!"
}

# ---------------------------------------------------------------------------
# Drill generation for one tier
# ---------------------------------------------------------------------------
generate_drill() {
  local tier=$1
  local name="${TIER_NAMES[$tier]}"
  local prompt="${DRILL_PROMPTS[$tier]}"
  local dir="${OUT_DIR}/drills/drill_${tier}"
  mkdir -p "$dir"

  log "====== DRILL TIER ${tier}: ${name} ======"

  # --- Base sprite (pixflux at 64x64 — must match animate-with-text output size) ---
  api_call "generate-image-pixflux" "$(cat <<ENDJSON
{
  "description": "${prompt}",
  "negative_description": "${NEG_DRILL}",
  "image_size": {"width": 64, "height": 64},
  "text_guidance_scale": ${TEXT_GUIDE},
  "outline": "${OUTLINE}",
  "shading": "${SHADING}",
  "detail": "${DETAIL}",
  "view": "${VIEW}",
  "direction": "${DIRECTION}",
  "no_background": true,
  "seed": $((tier * 10000 + 8002))
}
ENDJSON
)" "${dir}/base"
  pace

  # Pick base for animation reference
  local ref_file="${dir}/base.png"
  [[ ! -f "$ref_file" ]] && { log "SKIP: No base drill for tier ${tier}"; return 0; }
  local ref_json
  ref_json=$(img_b64 "$ref_file")

  local anim_desc="${DRILL_ANIM_DESC[$tier]}"

  # Helper for drill animation calls
  _drill_anim() {
    local anim_name="$1" action="$2" frames="$3" seed_offset="$4"
    api_call "animate-with-text" "$(cat <<ENDJSON
{
  "description": "${anim_desc}",
  "negative_description": "${NEG_DRILL}",
  "action": "${action}",
  "image_size": {"width": 64, "height": 64},
  "text_guidance_scale": 5,
  "image_guidance_scale": ${IMG_GUIDE},
  "n_frames": ${frames},
  "view": "${VIEW}",
  "direction": "${DIRECTION}",
  "reference_image": ${ref_json},
  "seed": $((tier * 10000 + seed_offset))
}
ENDJSON
)" "${dir}/${anim_name}" "multi"
    pace
  }

  _drill_anim "spin"   "spinning rapidly"                      8 9000
  _drill_anim "impact" "sparks flying from tip hitting rock"    4 9500

  log "Drill tier ${tier} (${name}) complete!"
}

# ---------------------------------------------------------------------------
# Shared effect sprites
# ---------------------------------------------------------------------------
generate_effects() {
  local dir="${OUT_DIR}/effects"
  mkdir -p "$dir"

  log "====== SHARED EFFECTS ======"

  # Helper: generate a base image, then animate from it
  # For effects, we generate a static base first (pixflux), then animate from that
  _effect_animate() {
    local name="$1" desc="$2" neg="$3" action="$4" frames="$5" seed="$6"
    local size="${7:-64}"

    # Step 1: generate static base as reference
    api_call "generate-image-pixflux" "$(cat <<ENDJSON
{
  "description": "${desc}",
  "negative_description": "${neg}",
  "image_size": {"width": ${size}, "height": ${size}},
  "text_guidance_scale": 10,
  "outline": "lineless",
  "shading": "${SHADING}",
  "detail": "${DETAIL}",
  "no_background": true,
  "seed": ${seed}
}
ENDJSON
)" "${dir}/${name}_ref"
    pace

    # Step 2: animate from the base
    local ref_file="${dir}/${name}_ref.png"
    if [[ -f "$ref_file" ]]; then
      local ref_json
      ref_json=$(img_b64 "$ref_file")
      api_call "animate-with-text" "$(cat <<ENDJSON
{
  "description": "${desc}",
  "negative_description": "${neg}",
  "action": "${action}",
  "image_size": {"width": 64, "height": 64},
  "text_guidance_scale": 8,
  "image_guidance_scale": 2.0,
  "n_frames": ${frames},
  "view": "side",
  "direction": "south",
  "reference_image": ${ref_json},
  "seed": $((seed + 100))
}
ENDJSON
)" "${dir}/${name}" "multi"
      pace
    else
      log "  SKIP animate ${name}: no base reference generated"
    fi
  }

  # Small explosion (dynamite)
  _effect_animate "explosion_small" \
    "fiery explosion burst, orange yellow flames with black smoke, shockwave ring, pixel art game effect" \
    "character, vehicle, text, watermark" \
    "exploding outward from center with expanding fireball and smoke ring" \
    8 77001

  # Large explosion (plastic explosive) — static only, 128x128
  api_call "generate-image-pixflux" "$(cat <<ENDJSON
{
  "description": "massive explosion fireball, bright white-hot center with orange red flames expanding outward, debris and shockwave, pixel art game effect sprite",
  "negative_description": "character, vehicle, text",
  "image_size": {"width": 128, "height": 128},
  "text_guidance_scale": 10,
  "outline": "lineless",
  "shading": "${SHADING}",
  "detail": "${DETAIL}",
  "no_background": true,
  "seed": 77002
}
ENDJSON
)" "${dir}/explosion_large"
  pace

  # Engine exhaust flame
  _effect_animate "exhaust" \
    "small rocket engine exhaust flame, bright orange-white fire plume pointing downward, pixel art effect" \
    "vehicle, character, text" \
    "flickering flame exhaust burning with varying intensity" \
    6 77003

  # Drill sparks
  _effect_animate "sparks" \
    "hot metal sparks spraying upward, bright orange-yellow spark particles, welding sparks effect, pixel art" \
    "character, vehicle, text" \
    "sparks spraying and bouncing in different directions" \
    6 77004

  # Ore pickup sparkle
  _effect_animate "ore_sparkle" \
    "shimmering sparkle collection effect, bright twinkling star particles converging to center, golden glitter, pixel art" \
    "character, vehicle, text" \
    "sparkle particles converging inward then flashing bright" \
    6 77005

  # Dust cloud (landing/surface)
  _effect_animate "dust" \
    "brown dust cloud puff expanding outward along ground, dirt particles settling, pixel art effect" \
    "character, vehicle, text" \
    "dust cloud expanding outward then dissipating and settling" \
    6 77006

  # Shield bubble (for quantum+ tiers) — static only, 128x128
  api_call "generate-image-pixflux" "$(cat <<ENDJSON
{
  "description": "translucent blue energy shield bubble, hexagonal force field pattern, sci-fi protective barrier, glowing edges, pixel art game effect sprite",
  "negative_description": "character, vehicle, solid, opaque, text",
  "image_size": {"width": 128, "height": 128},
  "text_guidance_scale": 10,
  "outline": "lineless",
  "shading": "${SHADING}",
  "detail": "${DETAIL}",
  "no_background": true,
  "seed": 77007
}
ENDJSON
)" "${dir}/shield"
  pace

  # Energy aura (for legendary tier)
  _effect_animate "aura" \
    "golden ethereal energy aura, radiant light particles orbiting in circle, divine glow effect, pixel art" \
    "character, vehicle, text" \
    "energy particles orbiting and pulsing with radiant golden light" \
    8 77008

  # Warning flash (low fuel / low hull indicator)
  _effect_animate "warning" \
    "red warning light flash, pulsing red danger indicator glow, emergency alert, pixel art" \
    "character, vehicle, text" \
    "red light pulsing on and off with urgency, bright flash then dim" \
    4 77009

  log "Effects generation complete!"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "============================================"
  log "   MOTHERLODE SPRITE GENERATOR"
  log "   ~82 API calls, ~250+ sprite frames"
  log "============================================"

  local mode="${1:-all}"
  local tier="${2:-}"

  case "$mode" in
    hull)
      if [[ -n "$tier" ]]; then
        generate_hull "$tier"
      else
        for t in 0 1 2 3 4 5; do generate_hull "$t"; done
      fi
      ;;
    drill)
      if [[ -n "$tier" ]]; then
        generate_drill "$tier"
      else
        for t in 0 1 2 3 4 5; do generate_drill "$t"; done
      fi
      ;;
    effects)
      generate_effects
      ;;
    all)
      for t in 0 1 2 3 4 5; do generate_hull "$t"; done
      for t in 0 1 2 3 4 5; do generate_drill "$t"; done
      generate_effects
      ;;
    *)
      echo "Usage: $0 [all|hull|drill|effects] [tier_number]"
      exit 1
      ;;
  esac

  log "============================================"
  log "COMPLETE! API calls: ${call_count}, Failures: ${fail_count}"
  log "Output: ${OUT_DIR}/"
  log "============================================"
}

main "$@"
