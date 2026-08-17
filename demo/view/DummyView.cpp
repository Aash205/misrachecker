// Deliberately uses a C-style cast, which the best-effort ruleset flags
// via modernize-avoid-c-style-cast (approximates MISRA C++ Rule 5-2-4:
// C-style casts should not be used). Uses a numeric (not pointer-width-
// dependent) cast, and no standard-library includes, so it compiles
// identically on host and on a bare-metal ARM target without a sysroot.
int dummy_view_scale(double input)
{
    int value = (int)input;
    return value;
}
