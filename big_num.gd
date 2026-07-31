class_name BigNum
extends RefCounted
# ================= BIG NUM v2.1.0 =================
# v2.0.0: Mantissa changed from int to float, giving full
#         precision between exponent tiers. from_int(1500)
#         now correctly stores m=1.5, e=1 instead of
#         truncating to m=1, e=1. to_int() reconstructs
#         exactly for values that fit in a GDScript int.
#         All arithmetic updated for float mantissa.
#         Display and save/load updated accordingly.
# v2.1.0: to_int() now clamps to INT64_MAX instead of
#         silently wrapping once a value exceeds ~9.2e18 —
#         late-game totals routinely exceed that range.
#         Added floor_to_whole() for "round to whole units"
#         use sites (e.g. save-load scrubbing) that used to
#         round-trip through the now-lossy to_int()/from_int().
#
# Stored as mantissa (1.0–999.999...) × 1000^exponent.
# Zero is represented as m=0.0, e=0.
#
# Usage:
#   var a = BigNum.from_int(1500)
#   var b = BigNum.from_int(500)
#   var c = a.add(b)
#   print(c.to_display_string())  # "2000"

var m: float = 0.0  # mantissa: 0.0 or 1.0–999.999...
var e: int   = 0    # exponent: power of 1000


# ==================================================
# CONSTRUCTORS
# ==================================================
static func zero() -> BigNum:
    var b = BigNum.new()
    b.m = 0.0
    b.e = 0
    return b


static func one() -> BigNum:
    return BigNum.from_int(1)


static func from_int(n: int) -> BigNum:
    var b = BigNum.new()
    if n <= 0:
        b.m = 0.0
        b.e = 0
        return b
    b.m = float(n)
    b.e = 0
    b._normalize()
    return b


static func from_float(f: float) -> BigNum:
    var b = BigNum.new()
    if f <= 0.0:
        b.m = 0.0
        b.e = 0
        return b
    b.m = f
    b.e = 0
    b._normalize()
    return b


static func from_me(mantissa: float, exponent: int) -> BigNum:
    var b = BigNum.new()
    b.m = mantissa
    b.e = exponent
    b._normalize()
    return b


static func from_string(s) -> BigNum:
    # Expects format produced by to_save_string: "m:e"
    # where m is a float string and e is an int string.
    # `s` is deliberately untyped: this is the primary sanitizer for every
    # BigNum-valued save field in load_save_data() (~40 call sites), so it
    # has to survive a corrupted save putting the wrong type at that key —
    # not just malformed string content. A typed `s: String` parameter
    # crashes/hangs the engine when the argument is a Dictionary or Array
    # (confirmed directly) rather than raising a catchable error, since the
    # mismatch happens at the call boundary before this body ever runs.
    if typeof(s) != TYPE_STRING:
        return BigNum.zero()
    var parts = s.split(":")
    if parts.size() != 2:
        return BigNum.zero()
    var b = BigNum.new()
    b.m = float(parts[0])
    b.e = int(parts[1])
    return b


# ==================================================
# NORMALIZATION
# Keeps mantissa in range [1.0, 1000.0).
# Zero is always m=0.0, e=0.
# ==================================================
func _normalize() -> void:
    # Every arithmetic entry point (from_float/from_me/mul_float/add/sub/
    # mul/etc.) funnels through here, so this is the one place that needs
    # to catch a non-finite mantissa. NaN/Infinity compare false against
    # everything, including themselves — `m <= 0.0` above doesn't catch
    # them, so they fall through to the while loops below. NaN just sits
    # there forever failing both loop conditions (m >= 1000.0 and m < 1.0
    # are both false for NaN), which is merely wrong, not fatal — but
    # +Infinity divided by 1000.0 is still +Infinity, so `while m >= 1000.0:
    # m /= 1000.0` never terminates. Confirmed directly: BigNum.from_float(
    # 1.0/0.0) hangs the engine. A legitimate float division with a zero or
    # near-zero denominator anywhere upstream (a spark-cap fraction, a rate
    # calculation, etc.) reaching from_float()/mul_float() is enough to
    # trigger this — no corrupted save required.
    if is_nan(m) or is_inf(m):
        m = 0.0
        e = 0
        return
    if m <= 0.0:
        m = 0.0
        e = 0
        return
    while m >= 1000.0:
        m /= 1000.0
        e += 1
    while m < 1.0 and m > 0.0:
        m *= 1000.0
        e -= 1


# ==================================================
# ARITHMETIC
# ==================================================
func add(other: BigNum) -> BigNum:
    if other.is_zero():
        return self.copy()
    if self.is_zero():
        return other.copy()

    var result = BigNum.new()
    var diff = e - other.e

    if diff == 0:
        result.m = m + other.m
        result.e = e
    elif diff > 0:
        if diff >= 7:
            # other is negligible at this scale
            return self.copy()
        # Scale self up to other's exponent space
        var self_scaled = m
        for i in diff:
            self_scaled *= 1000.0
        result.m = self_scaled + other.m
        result.e = other.e
    else:
        var abs_diff = -diff
        if abs_diff >= 7:
            return other.copy()
        var other_scaled = other.m
        for i in abs_diff:
            other_scaled *= 1000.0
        result.m = m + other_scaled
        result.e = e

    result._normalize()
    return result


func sub(other: BigNum) -> BigNum:
    # Returns zero if other >= self (no negatives)
    if other.is_zero():
        return self.copy()
    if is_less_than(other) or equals(other):
        return BigNum.zero()

    var result = BigNum.new()
    var diff = e - other.e

    if diff == 0:
        result.m = m - other.m
        result.e = e
    elif diff > 0:
        if diff >= 7:
            return self.copy()
        var self_scaled = m
        for i in diff:
            self_scaled *= 1000.0
        result.m = self_scaled - other.m
        result.e = other.e
    else:
        # self.e < other.e but self > other — shouldn't happen
        return BigNum.zero()

    result._normalize()
    return result


func mul(other: BigNum) -> BigNum:
    if is_zero() or other.is_zero():
        return BigNum.zero()
    var result = BigNum.new()
    result.m = m * other.m
    result.e = e + other.e
    result._normalize()
    return result


func mul_int(n: int) -> BigNum:
    if is_zero() or n <= 0:
        return BigNum.zero()
    var result = BigNum.new()
    result.m = m * float(n)
    result.e = e
    result._normalize()
    return result


func mul_float(f: float) -> BigNum:
    if is_zero() or f <= 0.0:
        return BigNum.zero()
    var result = BigNum.new()
    result.m = m * f
    result.e = e
    result._normalize()
    return result


func div_int(n: int) -> BigNum:
    if is_zero() or n <= 0:
        return BigNum.zero()
    var result = BigNum.new()
    result.m = m / float(n)
    result.e = e
    result._normalize()
    return result
    
    
func div_int_floor(n: int) -> BigNum:
    # Integer division that floors to zero for sub-1 results.
    # Use this when dividing resource counts to get whole-unit caps.
    if is_zero() or n <= 0:
        return BigNum.zero()
    # If the value is less than n, result floors to zero
    if is_less_than(BigNum.from_int(n)):
        return BigNum.zero()
    var result = BigNum.new()
    result.m = m / float(n)
    result.e = e
    result._normalize()
    result.m = floor(result.m)
    if result.m <= 0.0:
        return BigNum.zero()
    # If normalization pushed e negative, the result is fractional — floor to zero
    if result.e < 0:
        return BigNum.zero()
    return result


# ==================================================
# COMPARISON
# ==================================================
func is_zero() -> bool:
    return m <= 0.0


func equals(other: BigNum) -> bool:
    if e != other.e:
        return false
    return abs(m - other.m) < 0.0001


func is_greater_than(other: BigNum) -> bool:
    if is_zero():
        return false
    if other.is_zero():
        return m > 0.0
    if e != other.e:
        return e > other.e
    return m > other.m


func is_less_than(other: BigNum) -> bool:
    if other.is_zero():
        return false      # BigNum never stores negatives; nothing is < 0
    if is_zero():
        return other.m > 0.0
    if e != other.e:
        return e < other.e
    return m < other.m


func is_greater_or_equal(other: BigNum) -> bool:
    return not is_less_than(other)


func is_less_or_equal(other: BigNum) -> bool:
    return not is_greater_than(other)


# ==================================================
# CONVERSION
# ==================================================
const INT64_MAX: int = 9223372036854775807

func to_int() -> int:
    # Clamps rather than silently wrapping: a naive float->int cast past
    # ~9.2e18 (roughly e >= 6 with a large mantissa) produces garbage,
    # possibly negative, once it exceeds GDScript's 64-bit int range. Late-
    # game resource totals routinely exceed that range, so any caller that
    # needs an exact value at that scale should use to_float() instead —
    # this only guarantees a safe, ordering-preserving saturation.
    if is_zero():
        return 0
    if e < 0:
        return 0    # fractional value, rounds to 0
    var result: float = m
    for i in e:
        result *= 1000.0
        if result > 9.0e18:
            return INT64_MAX
    if result > 9.0e18:
        return INT64_MAX
    return int(result)


func to_float() -> float:
    # Safe float approximation for any scale.
    # Use this for bar calculations and display ratios.
    if is_zero():
        return 0.0
    var result = m
    if e != 0:
        result *= pow(1000.0, e)
    return result


func floor_to_whole() -> BigNum:
    # Floors to the nearest whole number entirely in float/BigNum space —
    # no int64 round-trip, so this stays correct at any magnitude, unlike
    # the old from_int(x.to_int()) pattern it replaces (silently corrupted
    # once x exceeded to_int()'s int64 range). At scales far beyond where a
    # sub-1 "fractional remnant" could ever matter, float64's own precision
    # limit makes floor() effectively a no-op, which is the correct outcome.
    if is_zero():
        return BigNum.zero()
    return BigNum.from_float(floor(to_float()))


func copy() -> BigNum:
    var b = BigNum.new()
    b.m = m
    b.e = e
    return b


# ==================================================
# SERIALIZATION
# ==================================================
func to_save_string() -> String:
    return "%s:%d" % [str(m), e]


# ==================================================
# DISPLAY
# ==================================================
func to_display_string() -> String:
    if is_zero():
        return "0"

    # Reconstruct base-10 exponent
    # actual value = m * 1000^e
    # base-10 exponent = e*3 + floor(log10(m))
    var base10_exp: int = e * 3
    var mantissa_f: float = m
    while mantissa_f >= 10.0:
        mantissa_f /= 10.0
        base10_exp += 1

    if base10_exp < 4:
        # Show exact value for small numbers (up to 9999)
        var exact = to_float()
        if exact == float(int(exact)):
            return str(int(exact))
        return "%.1f" % exact

    # Scientific notation
    if base10_exp >= 1000:
        var exp_exp := 0
        var ev := float(base10_exp)
        while ev >= 10.0:
            ev /= 10.0
            exp_exp += 1
        return "1e1e%d" % exp_exp

    var mantissa_str = "%.2f" % mantissa_f
    mantissa_str = mantissa_str.trim_suffix("0").trim_suffix(".")
    return mantissa_str + "e" + str(base10_exp)
