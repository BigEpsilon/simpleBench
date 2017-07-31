/**
Example application
Copyright: Copyright Nouredine Hussain 2017.
Authors: Nouredine Hussain
License: $(LINK3 http://www.boost.org/LICENSE_1_0.txt, Boost Software License - Version 1.0).
*/

module app;


import std.stdio;
import std.format;
import std.algorithm.iteration : sum, reduce, map, joiner;
import std.algorithm.comparison: max, min;
import std.range;
import core.time;
import std.json;

import benchmark;
import stats;


immutable N = 25;
// Function to bench
ulong fib_rec(immutable int n){
  if(n <= 0)
    return 0;
  else if(n==1 || n==2)
    return 1;
  else
    return fib_rec(n-1) + fib_rec(n-2);
}


// Function to bench
ulong fib_for_loop(immutable int n) {
    ulong a=0, b=1;
    for(int i=0; i < n; ++i) {
      auto t = b;
      b = a + b;
      a = t;
    }
    return a;
  }


// The proper test function
void test_fib_rec(ref Bencher bencher){
  int n=N; // Init variables and allocate memory
  bencher.iter((){
      return fib_rec(n); // The real code to bench
  });
}



void main()
{
  // The test function have to be static
  static void test_fib_for_loop(ref Bencher bencher){
    int n=N;
    bencher.iter((){
        return fib_for_loop(n);
    });
  }

  assert(fib_for_loop(N) == fib_rec(N));
  // Run the benchmarks
  auto br = BenchMain!(test_fib_rec, test_fib_for_loop);
  // Convert the results to JSON
  writeln(br.toJSON.toPrettyString);

}
