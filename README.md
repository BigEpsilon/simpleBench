# SimpleBench

This is a small benchmarking library for the D programming language. I wrote it when I started playing with the D programming language because I needed simple benchmarking utilities that where not available at that time.


The library is heavily inspired by the integrated benchmarking utilities of the Rust compiler.

## Installation

Add simplebench to your dependencies in your dub.json file.

## USAGE

Example:

    import std.stdio;
    import std.json;

    import simplebench;

    immutable N = 25;
    // Functions to bench
    ulong fib_rec(immutable int n){
     ...
    }
    // Function to bench
    ulong fib_for_loop(immutable int n) {
        ...
    }

    // The proper test function
    void test_fib_rec(ref Bencher bencher){
      int n=N; // Init variables, allocate memory ...
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
