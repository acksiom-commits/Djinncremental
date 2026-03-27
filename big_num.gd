class_name BigNum
extends RefCounted
# ================= BIG NUM v2.0.0 =================
# v2.0.0: Mantissa changed from int to float, giving full
#         precision between exponent tiers. from_int(1500)
#         now correctly stores m=1.5, e=1 instead of
#         truncating to m=1, e=1. to_int() reconstructs
#         exactly for values that fit in a GDScript int.
#         All arithmetic updated for float mantissa.
#         Display and save/load updated accordingly.
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


static func from_string(s: String) -> BigNum:
    # Expects format produced by to_save_string: "m:e"
    # where m is a float string and e is an int string.
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
    if e != other.e:
        return e > other.e
    return m > other.m


func is_less_than(other: BigNum) -> bool:
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
func to_int() -> int:
    # Reconstructs exact int for values that fit.
    # At large exponents this will overflow — use
    # to_float() for display/bar approximations instead.
    if is_zero():
        return 0
    var result = m
    for i in e:
        result *= 1000.0
    return int(result)


func to_float() -> float:
    # Safe float approximation for any scale.
    # Use this for bar calculations and display ratios.
    if is_zero():
        return 0.0
    var result = m
    for i in e:
        result *= 1000.0
    return result


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
