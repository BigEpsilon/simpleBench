/**
benchmark module: implmentation of the benchmarking utilities.
Copyright: Copyright Nouredine Hussain 2017.
Authors: Nouredine Hussain
License: $(LINK3 http://www.boost.org/LICENSE_1_0.txt, Boost Software License - Version 1.0).
*/

module simplebench;

import stats;
import std.json;

import core.time: MonoTimeImpl, ClockType, ticksToNSecs, dur;

alias MonoTime = MonoTimeImpl!(ClockType.precise);

/// This function can be used to avoid unused results from being optimized (removed) by the compiler.
T black_box(T)(T dummy) {
asm {;}
return dummy;
}

public struct Bencher {

ulong iterations;
long ticks;
ulong bytes;
ulong total_ns;
ulong total_iterations;


public void iter(T, Args...)(T delegate(Args) inner, Args args){
  auto start = MonoTime.currTime.ticks;
  foreach(_;0..iterations){
    black_box(inner(args));
  }
  ticks = MonoTime.currTime.ticks - start;
}


public @property long ns_per_iter() {
  import std.algorithm : max;
  if(iterations == 0)
    return 0;
  else
    return (ticks / max(iterations, 1)).ticksToNSecs();
}

void bench_n(in ulong n, void function(ref Bencher) f) {
  iterations = n;
  f(this);
}


/// Benchmark a function by measuring its execution time N consecutive times, where N is chosen apropiatily based on one execution of the function.
Summary auto_bench(void function(ref Bencher) f) {
  import std.algorithm.comparison : max;
  import core.checkedint;

  ulong n = 1;
  bench_n(n, f);

  auto dpi = ns_per_iter();
  if(dpi==0){
    n = 1_000_000;
  } else {
    n = 1_000_000 / max(dpi, 1);
  }

  if(n==0) {
    n = 1;
  }

  total_ns = 0;
  total_iterations = 1;
  double[50] samples = 0.0;
  bool has_ovf = false;
  for(;;) {
    ulong loop_start = MonoTime.currTime.ticks;

    foreach(_, ref e; samples){
      bench_n(n, f);
      e = ns_per_iter;
    }
    if(!has_ovf){
      total_iterations = addu(cast(ulong)n, total_iterations, has_ovf);
      if(has_ovf) {
        total_iterations = 0;
      }
    }

    winsorize(samples, 5.0);
    auto summ = Summary(samples);

    foreach(_, ref e; samples){
      bench_n(5*n, f);
      e = ns_per_iter;
    }

    if(!has_ovf){
      total_iterations = addu(cast(ulong)5*n, total_iterations, has_ovf);
      if(has_ovf) {
        total_iterations = 0;
      }
    }

    winsorize(samples, 5.0);
    auto summ5 = Summary(samples);
    auto loop_run = (MonoTime.currTime.ticks - loop_start).ticksToNSecs();


    total_ns += loop_run;

    if(loop_run > dur!"msecs"(100).total!"nsecs" && summ.median_abs_dev_pct < 1.0 &&
       summ.median - summ5.median <= summ5.median_abs_dev){
      return summ5;
    }


    if(total_ns > dur!"seconds"(3).total!"nsecs") {
      return summ5;
    }


    bool ovf;
    muls(n, 10, ovf);
    if(ovf){
      return summ5;
    } else {
      n *= 2;
    }
  }
}
}

public struct BenchSamples {
public string name;
public Summary ns_iter_summ;
public ulong mb_s;
public ulong total_ns;
public ulong total_iterations;

public JSONValue toJSON() {

  JSONValue jj = ["name": name];
  jj.object["total_ns"] = JSONValue(total_ns);
  jj.object["total_iterations"] = JSONValue(total_iterations);
  jj.object["mb_s"] = JSONValue(mb_s);
  jj.object["ns_iter_summ"] = JSONValue(ns_iter_summ.toJSON);
  return jj;
}
}

public struct BenchmarksResults {
public BenchSamples[] samples;

public JSONValue toJSON() {

  JSONValue[] jjs;
  foreach(_, bs; samples){
    jjs ~= bs.toJSON;
  }
  JSONValue jj = ["BenchmarksResults": jjs];
  return jj;
}
}

/// Benchmark one function
BenchSamples benchmark(void function(ref Bencher) f) {
  import std.algorithm.comparison: max;
  Bencher bencher = {iterations: 0, ticks: 0, bytes: 0};

  auto ns_iter_summ = bencher.auto_bench(f);
  ulong ns_iter = max(cast(ulong)ns_iter_summ.median, 1);
  auto mb_s = bencher.bytes * 1000 / ns_iter;
  auto total_ns = bencher.total_ns;
  auto total_iterations = bencher.total_iterations;

  BenchSamples bs = {ns_iter_summ: ns_iter_summ,
                     mb_s: mb_s,
                     total_iterations: total_iterations,
                     total_ns: total_ns};
  return bs;
}

string nsecsToStr(ulong n){
  import std.format : format;

  string str;
  string[] lunits = ["ns", "us", "msec", "sec"];

  ulong counter = 1;
  foreach(_, ref unit; lunits){
    if(n < counter * 1000){
      str = format("%.6s %s", cast(double)n / counter, unit);
      break;
    }
    counter *= 1000;
  }
  return str;
  }

/// Benchmark multiple functions
public BenchmarksResults BenchMain(Functions...)(){
  import std.stdio;
  import std.format;
  import std.array : replicate;

  BenchmarksResults br;

  auto header = format("%25.25s | %30.30s | %15.15s | %15.15s | %15.15s | %15.15s |", 
                "Benchmark name", "Time/iter", "Best", "Worst", "Total", "Iterations");
  auto sep = "-".replicate(header.length);
  writeln(sep);
  writeln(header);
  writeln(sep);
  foreach(f; Functions){
    auto bs = benchmark(&f);
    bs.name = __traits(identifier, f);
    br.samples ~= bs;
    string str_per_iter= format("%s (+/- %s)", 
                    nsecsToStr(cast(ulong)bs.ns_iter_summ.median), 
                    nsecsToStr(cast(ulong)(bs.ns_iter_summ.max - bs.ns_iter_summ.min)));
    writef("%25.25s | %30.30s", bs.name, str_per_iter);
    writef(" | %15.15s | %15.15s", 
                    nsecsToStr(cast(ulong)bs.ns_iter_summ.min), 
                    nsecsToStr(cast(ulong)bs.ns_iter_summ.max));
    writef(" | %15.15s | %15.15s |\n", 
                    nsecsToStr(cast(ulong)bs.total_ns), 
                    format("%s",bs.total_iterations));
  }
  writeln(sep);

  return br;
}

unittest
{
  static void f1(ref Bencher bencher){
    import std.algorithm.iteration: sum;
    import std.array;

    bencher.iter((){
        return [1e20, 1.5, -1e20].sum();
    });
  }

  static void f2(ref Bencher bencher){
    import std.algorithm.iteration: sum, map;
    import std.range: iota;
    import std.array;
    immutable nums = [-1e30, 1e60, 1e30, 1.0, -1e60];
    auto v = iota(0, 500).map!(i => nums[i % 5]).array;
    bencher.iter((){
        return v.sum();
    });
  }
 
  benchmark(&f1);
  benchmark(&f2);
  BenchMain!(f1, f2);

  // black_box(benchmark(&f1));
  // black_box(benchmark(&f2));
  // black_box(BenchMain!(f1, f2));
}
