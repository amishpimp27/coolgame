extends Node
## The roll dice for conversation outcomes.
##
## Every chat option is a weighted roll whose chances depend on the girl's
## current affection tier (0=Stranger, 1=Friend, 2=Close, 3=Lover). Higher
## affection makes success more likely, but it is never guaranteed -- the Lover
## tier still carries a small chance of failure for the risky options.
##
## "Ask about herself" is not here; it never rolls (always +2 affection).
##
## Autoloaded as `Rolls`.

## Just Chat: index by tier -> [success, neutral]
const CHAT := [
	[0.55, 0.45],
	[0.65, 0.35],
	[0.78, 0.22],
	[0.90, 0.10],
]

## Compliment: index by tier -> [success, fail]
const COMPLIMENT := [
	[0.60, 0.40],
	[0.72, 0.28],
	[0.82, 0.18],
	[0.90, 0.10],
]

## Flirt: index by tier -> [success, neutral, fail]
const FLIRT := [
	[0.35, 0.35, 0.30],
	[0.50, 0.30, 0.20],
	[0.62, 0.25, 0.13],
	[0.72, 0.20, 0.08],
]


func _clamp_tier(tier: int) -> int:
	return clampi(tier, 0, 3)


## Cumulative roll against [weight, ...] summing to ~1.0; returns the index.
func _roll(weights: Array) -> int:
	var r := randf()
	var acc := 0.0
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			return i
	return weights.size() - 1


func roll_chat(tier: int) -> String:
	return ["success", "neutral"][_roll(CHAT[_clamp_tier(tier)])]


func roll_compliment(tier: int) -> String:
	return ["success", "fail"][_roll(COMPLIMENT[_clamp_tier(tier)])]


func roll_flirt(tier: int) -> String:
	return ["success", "neutral", "fail"][_roll(FLIRT[_clamp_tier(tier)])]


## Whole-number percentages, for the balance notes and the HUD.
func percent_chat(tier: int) -> Array:
	return [int(CHAT[_clamp_tier(tier)][0] * 100.0), int(CHAT[_clamp_tier(tier)][1] * 100.0)]


func percent_compliment(tier: int) -> Array:
	return [int(COMPLIMENT[_clamp_tier(tier)][0] * 100.0), int(COMPLIMENT[_clamp_tier(tier)][1] * 100.0)]


func percent_flirt(tier: int) -> Array:
	var w: Array = FLIRT[_clamp_tier(tier)]
	return [int(w[0] * 100.0), int(w[1] * 100.0), int(w[2] * 100.0)]