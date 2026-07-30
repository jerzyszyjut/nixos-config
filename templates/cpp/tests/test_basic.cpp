#include <catch2/catch_test_macros.hpp>

#include "lib.hpp"

TEST_CASE("add sums two integers", "[add]") {
  REQUIRE(add(2, 2) == 4);
  REQUIRE(add(-1, 1) == 0);
}
