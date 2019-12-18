# test cperl's op_clone:
# the structure must stay the same: inside ptrs must point to the same location,
# the types and fields must be properly copied.
# inside ptrs must be changed outside ptrs must stay the same.
# the result of op_clone must match the number of outside ptrs.
# needs an XS::APITest::op_clone_dump test function.

require XS::APItest;
