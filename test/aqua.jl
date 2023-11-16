using Aqua
using DisjunctiveProgramming

Aqua.test_all(DisjunctiveProgramming, deps_compat = false, ambiguities = false)
Aqua.test_deps_compat(DisjunctiveProgramming, check_extras = (ignore=[:Test, :HiGHS],))
Aqua.test_ambiguities(DisjunctiveProgramming)