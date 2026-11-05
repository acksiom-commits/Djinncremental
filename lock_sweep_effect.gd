extends RichTextEffect
## [sweep len=N]text[/sweep]: a bright band moves left to right across the
## text, over and over (author, 2026-11-04). Marks the purity lock that holds
## a PARENT Volition, so it can be told on sight from the plain-gold locks held
## by Child Volitions (root_ui.gd _lock_sweep_if_parent()).
##
## The band wraps: as it runs off the end of the label it comes straight back
## in at the beginning, with no pause or gap (author, 2026-11-04), so it is
## always somewhere on the label.
##
## `len` is the span's visible character count, so the band laps short and
## long names in the same time. The band's position comes from the clock, not
## the effect's own elapsed time, because root_ui.gd rewrites some of these
## labels every frame, which would restart a per-label timer.

## Seconds for one lap of the label. (Each pass first took 2.2 s, then 1.1 s
## once the author doubled the speed; that time included travel on and off
## the label plus a pause. Now a lap is the label alone, and 0.8 s keeps the
## band crossing a name like "Adaemant:" about as fast as at 1.1.)
const PERIOD: float = 0.8
## The band: a fully white core CORE characters either side of its centre,
## then a fade over FADE more (made brighter by the author, 2026-11-04: more
## of the band reaches full white). On a short label each is held to
## SHORT_FRACTION of its length, or the looping band would cover all of it.
const CORE: float = 1.5
const FADE: float = 1.5
const SHORT_FRACTION: float = 0.2
## Full white at full strength: the locks' gold (#ffdd77) is already bright,
## so a softer peak barely showed against it.
const PEAK := Color(1.0, 1.0, 1.0)
const STRENGTH: float = 1.0

var bbcode := "sweep"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
    var span: float = maxf(float(char_fx.env.get("len", 10)), 1.0)
    var core: float = minf(CORE, span * SHORT_FRACTION)
    var fade: float = maxf(minf(FADE, span * SHORT_FRACTION), 0.01)
    var t: float = fmod(Time.get_ticks_msec() / 1000.0, PERIOD) / PERIOD
    var centre: float = t * span
    # Distance from this character's middle to the band's centre, measured
    # round the loop, so the band leaving the right end is the band entering
    # the left.
    var d: float = fposmod(float(char_fx.relative_index) + 0.5 - centre, span)
    d = minf(d, span - d)
    var k: float = clampf(1.0 - (d - core) / fade, 0.0, 1.0)
    k = k * k * (3.0 - 2.0 * k)
    var c: Color = char_fx.color
    # The 🔒 is a colour emoji and ignores tint, so the band leaves it as is.
    # (A blink in time with the band was tried, 2026-11-04, and taken out by
    # the author as too much.)
    char_fx.color = Color(lerpf(c.r, PEAK.r, k * STRENGTH), lerpf(c.g, PEAK.g, k * STRENGTH),
        lerpf(c.b, PEAK.b, k * STRENGTH), c.a)
    return true
