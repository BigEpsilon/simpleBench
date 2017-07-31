/**
  This module is part of bencher package, a simple rewrite
  in the D programming language of the Rust standard benchmark
  module.

  Original Rust source : https://github.com/rust-lang/rust/blob/master/src/libtest/stats.rs

  This module contains data structures and algorithms for doing 
  statistics on benchmarks execution. The focus is put more on 
  precision than execution speed. The algorithms are written to
  fit for a particular use case and not intended to be used
  elsewhere.

  Authors: Nouredine Hussain
  Copyright: Copyright Nouredine Hussain 2017.
  License: $(LINK3 http://www.boost.org/LICENSE_1_0.txt, Boost Software License - Version 1.0).
*/

module stats;

import std.typecons : Tuple, tuple;
import std.range : empty;
import std.json;

/** 
  A structure that provides simple descriptive statistics
  on a univariate set of numeric samples.
*/
public struct Summary {

  /// Original rust comment : 
  /// Note: this method sacrifices performance at the altar of accuracy
  /// Depends on IEEE-754 arithmetic guarantees. See proof of correctness at:
  /// ["Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates"]
  /// (http://www.cs.cmu.edu/~quake-papers/robust-arithmetic.ps)
  public double sum,
    /// Original rust comment : 
    /// Minimum value of the samples.
    min,
    /// Original rust comment : 
    /// Maximum value of the samples.
    max,
    /// Original rust comment : 
    /// Arithmetic mean (average) of the samples: sum divided by sample-count.
    ///
    /// See: https://en.wikipedia.org/wiki/Arithmetic_mean
    mean,
    /// Original rust comment : 
    /// Median of the samples: value separating the lower half of the samples from the higher half.
    /// Equal to `percentile(50.0)`.
    ///
    /// See: https://en.wikipedia.org/wiki/Median
    median,
    /// Original rust comment : 
    /// Variance of the samples: bias-corrected mean of the squares of the differences of each
    /// sample from the sample mean. Note that this calculates the _sample variance_ rather than the
    /// population variance, which is assumed to be unknown. It therefore corrects the `(n-1)/n`
    /// bias that would appear if we calculated a population variance, by dividing by `(n-1)` rather
    /// than `n`.
    ///
    /// See: https://en.wikipedia.org/wiki/Variance
    var,
    /// Standard deviation: the square root of the sample variance.
    ///
    /// Note: this is not a robust statistic for non-normal distributions. Prefer the
    /// `median_abs_dev` for unknown distributions.
    ///
    /// See: https://en.wikipedia.org/wiki/Standard_deviation
    std_dev,
    /// Original rust comment : 
    /// Standard deviation as a percent of the mean value. See `std_dev` and `mean`.
    ///
    /// Note: this is not a robust statistic for non-normal distributions. Prefer the
    /// `median_abs_dev_pct` for unknown distributions.
    std_dev_pct,
    /// Original rust comment : 
    /// Scaled median of the absolute deviations of each sample from the sample median. This is a
    /// robust (distribution-agnostic) estimator of sample variability. Use this in preference to
    /// `std_dev` if you cannot assume your sample is normally distributed. Note that this is scaled
    /// by the constant `1.4826` to allow its use as a consistent estimator for the standard
    /// deviation.
    ///
    /// See: http://en.wikipedia.org/wiki/Median_absolute_deviation
    median_abs_dev,
    /// Original rust comment : 
    /// Median absolute deviation as a percent of the median. See `median_abs_dev` and `median`.
    median_abs_dev_pct,
    /// Original rust comment : 
    /// Inter-quartile range: the difference between the 25th percentile (1st quartile) and the 75th
    /// percentile (3rd quartile). See `quartiles`.
    ///
    /// See also: https://en.wikipedia.org/wiki/Interquartile_range
    iqr;

  /// Original rust comment : 
  /// Quartiles of the sample: three values that divide the sample into four equal groups, each
  /// with 1/4 of the data. The middle value is the median. See `median` and `percentile`. This
  /// function may calculate the 3 quartiles more efficiently than 3 calls to `percentile`, but
  /// is otherwise equivalent.
  ///
  /// See also: https://en.wikipedia.org/wiki/Quartile
  public Tuple!(double, double, double) quartiles;

  /**
    Construct a new summary of a sample set.
  */
  this(double[] samples){
    import std.algorithm.iteration: reduce;
    import std.algorithm.sorting: sort;
    import std.math : sqrt, isNaN;
    import std.array;

    double _min(double a, double b) {
      if(a.isNaN)
        return b;
      if(b.isNaN)
        return a;
      return a < b ? a:b;
    }

    double _max(double a, double b) {
      if(a.isNaN)
        return b;
      if(b.isNaN)
        return a;
      return a > b ? a:b;
    }

    bool _less(double a, double b) {
      import std.math : isNaN;

      if(a.isNaN)
        return false;
      if(b.isNaN)
        return true;
      return a < b;

    }

    double[] sorted_samples = samples.sort!(_less).array;
    sum = samples.sum();
    min = samples.reduce!(_min);
    max = samples.reduce!(_max);
    mean = sum / samples.length;
    median = sorted_samples.median_of_sorted();
    var = samples.var(mean);
    std_dev = var.sqrt();
    std_dev_pct = (std_dev/mean) * 100.0;
    median_abs_dev = sorted_samples.median_abs_dev_of_sorted(median);
    median_abs_dev_pct = median_abs_dev.median_abs_dev_pct(median);
    quartiles = sorted_samples.quartiles_of_sorted();
    iqr = quartiles[2] - quartiles[0];
  }

  /** 
    Serialize the summary in JSON format.
  */

  public JSONValue toJSON(){

    JSONValue jj = ["sum": sum];
    jj.object["min"] = JSONValue(min);
    jj.object["max"] = JSONValue(max);
    jj.object["mean"] = JSONValue(mean);
    jj.object["median"] = JSONValue(median);
    jj.object["var"] = JSONValue(var);
    jj.object["std_dev"] = JSONValue(std_dev);
    jj.object["std_dev_pct"] = JSONValue(std_dev_pct);
    jj.object["median_abs_dev"] = JSONValue(median_abs_dev);
    jj.object["median_abs_dev_pct"] = JSONValue(median_abs_dev_pct);
    jj.object["iqr"] = JSONValue(iqr);
    jj.object["quartiles"] = JSONValue([quartiles[0], quartiles[1], quartiles[2]]);
    return jj;
  }

}

private alias sumKahan sum;

// Kahan algo http://en.wikipedia.org/wiki/Kahan_summation_algorithm
private double sumKahan(double[] arr) {
    import std.math : abs;
    import std.algorithm.mutation: swap;
    import std.algorithm.iteration: fold;
    double[] partials;

    foreach(_, x; arr) {
        ulong j = 0;
        for(int i=0; i < partials.length; ++i) {
            auto y = partials[i];
            if(x.abs() < y.abs()) {
                swap(x, y);
            }
            immutable hi = x + y;
            immutable lo = y - (hi - x);
            if(lo != 0.0) {
              partials[j] = lo;
              j++;
            }
            x = hi;
        }
        if(j >= partials.length){
            partials ~= x;
        } else {
            partials[j] = x;
            partials.length = j+1;
        }
    }
    return partials.fold!((a, b) => a+b);
}


/// Original rust comment : 
/// Percentile: the value below which `pct` percent of the values in the samples fall. For example,
/// percentile(95.0) will return the value `v` such that 95% of the samples `s` in the samples
/// satisfy `s <= v`.
///
/// Calculated by linear interpolation between closest ranks.
///
/// See: http://en.wikipedia.org/wiki/Percentile
private double percentile_of_sorted(double[] sorted_arr, double pct){
  import std.math: floor;

  assert(!sorted_arr.empty);

  if(sorted_arr.length==1)
    return sorted_arr[0];
  if(pct == 100.0)
    return sorted_arr[$-1];
  assert(0.0 <= pct && pct <= 100.0);
  immutable length = sorted_arr.length -1;
  immutable rank = (pct / 100.0) * length;
  immutable lrank = rank.floor();
  immutable d = rank - lrank;
  immutable n = cast(size_t)lrank;
  immutable lo = sorted_arr[n];
  immutable hi = sorted_arr[n+1];
  return lo + (hi -lo) *d;


}

private double median_of_sorted(double[] sorted_arr) {
  return percentile_of_sorted(sorted_arr, 50.0);
}

private double var(double[] arr, immutable double mean) {
  if(arr.length < 2)
    return 0.0;
  double v = 0;
  foreach(_, ref e; arr){
    auto x = e - mean;
    v = v + x*x;
  }
  auto denom = arr.length - 1;

  return v / denom;
}


private double median_abs_dev_of_sorted(double[] sorted, immutable double median) {
  import std.algorithm.iteration: map;
  import std.algorithm.sorting: sort;
  import std.math: abs;
  import std.array;

  static bool _less(double a, double b) {
    import std.math : isNaN;

    if(a.isNaN)
      return false;
    if(b.isNaN)
      return true;
    return a < b;

  }
  auto abs_devs = sorted.map!(a => abs(median-a))
                        .array
                        .sort!(_less)
                        .array;

  // from rust dev comment:
  // This constant is derived by smarter statistics brains than me, but it is
  // consistent with how R and other packages treat the MAD.
  immutable number = 1.4826;
  return abs_devs.median_of_sorted() * number;
}

private double median_abs_dev_pct(double median_abs_dev, double median) {
  return (median_abs_dev/median)*100.0;
}

private double iqr(double[] samples) {
  return 0;
}

private auto quartiles_of_sorted(double[] sorted) {
  auto a = sorted.percentile_of_sorted(25.0);
  auto b = sorted.percentile_of_sorted(50.0);
  auto c = sorted.percentile_of_sorted(75.0);

  return tuple(a, b, c);
}

/// Original rust comment
/// Winsorize a set of samples, replacing values above the `100-pct` percentile
/// and below the `pct` percentile with those percentiles themselves. This is a
/// way of minimizing the effect of outliers, at the cost of biasing the sample.
/// It differs from trimming in that it does not change the number of samples,
/// just changes the values of those that are outliers.
///
/// See: http://en.wikipedia.org/wiki/Winsorising
public void winsorize(double[] arr, double pct){
  import std.algorithm.sorting: sort;
  import std.array;

  bool _less(double a, double b) {
    import std.math : isNaN;

    if(a.isNaN)
      return false;
    if(b.isNaN)
      return true;
    return a < b;

  }

  auto sorted = arr.array.sort!(_less).array();
  immutable lo = percentile_of_sorted(sorted , pct);
  immutable hi = percentile_of_sorted(sorted, 100.0-pct);
  foreach(_, ref e; arr){
    if(e > hi){
      e = hi;
    } else if(e < lo) {
      e = lo;
    }
  }
}


unittest 
{
  double[5] samples = [1.0, 2.0, double.nan, 4.0, 3.0];

  auto summ = Summary(samples);

  assert(summ.min == 1.0);
  assert(summ.max == 4.0);
}

private void check(double[] samples, ref Summary summ) {
    import std.math: approxEqual;
    auto summ2 = Summary(samples);

    assert(summ.sum == summ2.sum);
    assert(summ.min == summ2.min);
    assert(summ.max == summ2.max);
    assert(summ.mean == summ2.mean);
    assert(summ.median == summ2.median);
    assert(summ.quartiles == summ2.quartiles);
    assert(summ.iqr == summ2.iqr);

    assert(approxEqual(summ.var, summ2.var));
    assert(approxEqual(summ.std_dev, summ2.std_dev));
    assert(approxEqual(summ.std_dev_pct, summ2.std_dev_pct));
    assert(approxEqual(summ.median_abs_dev, summ2.median_abs_dev));
    assert(approxEqual(summ.median_abs_dev_pct, summ2.median_abs_dev_pct));
}

unittest
{
  // norm2
  auto samples = [958.0000000000, 
                  924.0000000000];

  auto summ = Summary();
  summ.sum= 1882.0000000000;
  summ.min= 924.0000000000;
  summ.max= 958.0000000000;
  summ.mean= 941.0000000000;
  summ.median= 941.0000000000;
  summ.var= 578.0000000000;
  summ.std_dev= 24.0416305603;
  summ.std_dev_pct= 2.5549022912;
  summ.median_abs_dev= 25.2042000000;
  summ.median_abs_dev_pct= 2.6784484591;
  summ.quartiles= tuple(932.5000000000, 941.0000000000, 949.5000000000);
  summ.iqr= 17.0000000000;

  check(samples, summ);
}

unittest
{
  // norm10narrow
  auto samples = [966.0000000000,
                  985.0000000000,
                  1110.0000000000,
                  848.0000000000,
                  821.0000000000,
                  975.0000000000,
                  962.0000000000,
                  1157.0000000000,
                  1217.0000000000,
                  955.0000000000];

  auto summ = Summary();
  summ.sum= 9996.0000000000;
  summ.min= 821.0000000000;
  summ.max= 1217.0000000000;
  summ.mean= 999.6000000000;
  summ.median= 970.5000000000;
  summ.var= 16050.7111111111;
  summ.std_dev= 126.6914010938;
  summ.std_dev_pct= 12.6742097933;
  summ.median_abs_dev= 102.2994000000;
  summ.median_abs_dev_pct= 10.5408964451;
  summ.quartiles= tuple(956.7500000000, 970.5000000000, 1078.7500000000);
  summ.iqr= 122.0000000000;

  check(samples, summ);
}


unittest
{
  // norm10medium
  auto samples = [954.0000000000,
                  1064.0000000000,
                  855.0000000000,
                  1000.0000000000,
                  743.0000000000,
                  1084.0000000000,
                  704.0000000000,
                  1023.0000000000,
                  357.0000000000,
                  869.0000000000];

  auto summ = Summary();
  summ.sum= 8653.0000000000;
  summ.min= 357.0000000000;
  summ.max= 1084.0000000000;
  summ.mean= 865.3000000000;
  summ.median= 911.5000000000;
  summ.var= 48628.4555555556;
  summ.std_dev= 220.5186059170;
  summ.std_dev_pct= 25.4846418487;
  summ.median_abs_dev= 195.7032000000;
  summ.median_abs_dev_pct= 21.4704552935;
  summ.quartiles= tuple(771.0000000000, 911.5000000000, 1017.2500000000);
  summ.iqr= 246.2500000000;

  check(samples, summ);
}

unittest
{
  // norm10wide
  auto samples = [505.0000000000,
                  497.0000000000,
                  1591.0000000000,
                  887.0000000000,
                  1026.0000000000,
                  136.0000000000,
                  1580.0000000000,
                  940.0000000000,
                  754.0000000000,
                  1433.0000000000];

  auto summ = Summary();
  summ.sum= 9349.0000000000;
  summ.min= 136.0000000000;
  summ.max= 1591.0000000000;
  summ.mean= 934.9000000000;
  summ.median= 913.5000000000;
  summ.var= 239208.9888888889;
  summ.std_dev= 489.0899599142;
  summ.std_dev_pct= 52.3146817750;
  summ.median_abs_dev= 611.5725000000;
  summ.median_abs_dev_pct= 66.9482758621;
  summ.quartiles= tuple(567.2500000000, 913.5000000000, 1331.2500000000);
  summ.iqr= 764.0000000000;

  check(samples, summ);
}

unittest
{
  // norm25verynarrow
  auto samples = [991.0000000000,
                  1018.0000000000,
                  998.0000000000,
                  1013.0000000000,
                  974.0000000000,
                  1007.0000000000,
                  1014.0000000000,
                  999.0000000000,
                  1011.0000000000,
                  978.0000000000,
                  985.0000000000,
                  999.0000000000,
                  983.0000000000,
                  982.0000000000,
                  1015.0000000000,
                  1002.0000000000,
                  977.0000000000,
                  948.0000000000,
                  1040.0000000000,
                  974.0000000000,
                  996.0000000000,
                  989.0000000000,
                  1015.0000000000,
                  994.0000000000,
                  1024.0000000000];

  auto summ = Summary();
  summ.sum= 24926.0000000000;
  summ.min= 948.0000000000;
  summ.max= 1040.0000000000;
  summ.mean= 997.0400000000;
  summ.median= 998.0000000000;
  summ.var= 393.2066666667;
  summ.std_dev= 19.8294393937;
  summ.std_dev_pct= 1.9888308788;
  summ.median_abs_dev= 22.2390000000;
  summ.median_abs_dev_pct= 2.2283567134;
  summ.quartiles= tuple(983.0000000000, 998.0000000000, 1013.0000000000);
  summ.iqr= 30.0000000000;

  check(samples, summ);
}

unittest
{
  // exp10a
  auto samples = [23.0000000000,
                  11.0000000000,
                  2.0000000000,
                  57.0000000000,
                  4.0000000000,
                  12.0000000000,
                  5.0000000000,
                  29.0000000000,
                  3.0000000000,
                  21.0000000000];

  auto summ = Summary();
  summ.sum= 167.0000000000;
  summ.min= 2.0000000000;
  summ.max= 57.0000000000;
  summ.mean= 16.7000000000;
  summ.median= 11.5000000000;
  summ.var= 287.7888888889;
  summ.std_dev= 16.9643416875;
  summ.std_dev_pct= 101.5828843560;
  summ.median_abs_dev= 13.3434000000;
  summ.median_abs_dev_pct= 116.0295652174;
  summ.quartiles= tuple(4.2500000000, 11.5000000000, 22.5000000000);
  summ.iqr= 18.2500000000;
        
  check(samples, summ);
}

unittest
{
  // exp10b
  auto samples = [24.0000000000,
                  17.0000000000,
                  6.0000000000,
                  38.0000000000,
                  25.0000000000,
                  7.0000000000,
                  51.0000000000,
                  2.0000000000,
                  61.0000000000,
                  32.0000000000];

  auto summ = Summary();
  summ.sum= 263.0000000000;
  summ.min= 2.0000000000;
  summ.max= 61.0000000000;
  summ.mean= 26.3000000000;
  summ.median= 24.5000000000;
  summ.var= 383.5666666667;
  summ.std_dev= 19.5848580967;
  summ.std_dev_pct= 74.4671410520;
  summ.median_abs_dev= 22.9803000000;
  summ.median_abs_dev_pct= 93.7971428571;
  summ.quartiles= tuple(9.5000000000, 24.5000000000, 36.5000000000);
  summ.iqr= 27.0000000000;
        
  check(samples, summ);
}

unittest
{
  // exp10c
  auto samples = [71.0000000000,
                  2.0000000000,
                  32.0000000000,
                  1.0000000000,
                  6.0000000000,
                  28.0000000000,
                  13.0000000000,
                  37.0000000000,
                  16.0000000000,
                  36.0000000000];

  auto summ = Summary();
  summ.sum= 242.0000000000;
  summ.min= 1.0000000000;
  summ.max= 71.0000000000;
  summ.mean= 24.2000000000;
  summ.median= 22.0000000000;
  summ.var= 458.1777777778;
  summ.std_dev= 21.4050876611;
  summ.std_dev_pct= 88.4507754589;
  summ.median_abs_dev= 21.4977000000;
  summ.median_abs_dev_pct= 97.7168181818;
  summ.quartiles= tuple(7.7500000000, 22.0000000000, 35.0000000000);
  summ.iqr= 27.2500000000;
        
  check(samples, summ);
}

unittest
{
  // exp25
  auto samples = [3.0000000000,
                  24.0000000000,
                  1.0000000000,
                  19.0000000000,
                  7.0000000000,
                  5.0000000000,
                  30.0000000000,
                  39.0000000000,
                  31.0000000000,
                  13.0000000000,
                  25.0000000000,
                  48.0000000000,
                  1.0000000000,
                  6.0000000000,
                  42.0000000000,
                  63.0000000000,
                  2.0000000000,
                  12.0000000000,
                  108.0000000000,
                  26.0000000000,
                  1.0000000000,
                  7.0000000000,
                  44.0000000000,
                  25.0000000000,
                  11.0000000000];

  auto summ = Summary();
  summ.sum= 593.0000000000;
  summ.min= 1.0000000000;
  summ.max= 108.0000000000;
  summ.mean= 23.7200000000;
  summ.median= 19.0000000000;
  summ.var= 601.0433333333;
  summ.std_dev= 24.5161851301;
  summ.std_dev_pct= 103.3565983562;
  summ.median_abs_dev= 19.2738000000;
  summ.median_abs_dev_pct= 101.4410526316;
  summ.quartiles= tuple(6.0000000000, 19.0000000000, 31.0000000000);
  summ.iqr= 25.0000000000;
        
  check(samples, summ);
}

unittest
{
  // binom25
  auto samples = [18.0000000000,
                  17.0000000000,
                  27.0000000000,
                  15.0000000000,
                  21.0000000000,
                  25.0000000000,
                  17.0000000000,
                  24.0000000000,
                  25.0000000000,
                  24.0000000000,
                  26.0000000000,
                  26.0000000000,
                  23.0000000000,
                  15.0000000000,
                  23.0000000000,
                  17.0000000000,
                  18.0000000000,
                  18.0000000000,
                  21.0000000000,
                  16.0000000000,
                  15.0000000000,
                  31.0000000000,
                  20.0000000000,
                  17.0000000000,
                  15.0000000000];

  auto summ = Summary();
  summ.sum= 514.0000000000;
  summ.min= 15.0000000000;
  summ.max= 31.0000000000;
  summ.mean= 20.5600000000;
  summ.median= 20.0000000000;
  summ.var= 20.8400000000;
  summ.std_dev= 4.5650848842;
  summ.std_dev_pct= 22.2037202539;
  summ.median_abs_dev= 5.9304000000;
  summ.median_abs_dev_pct= 29.6520000000;
  summ.quartiles= tuple(17.0000000000, 20.0000000000, 24.0000000000);
  summ.iqr= 7.0000000000;

  check(samples, summ);
}

unittest
{
  // pois25lambda30
  auto samples = [27.0000000000,
                  33.0000000000,
                  34.0000000000,
                  34.0000000000,
                  24.0000000000,
                  39.0000000000,
                  28.0000000000,
                  27.0000000000,
                  31.0000000000,
                  28.0000000000,
                  38.0000000000,
                  21.0000000000,
                  33.0000000000,
                  36.0000000000,
                  29.0000000000,
                  37.0000000000,
                  32.0000000000,
                  34.0000000000,
                  31.0000000000,
                  39.0000000000,
                  25.0000000000,
                  31.0000000000,
                  32.0000000000,
                  40.0000000000,
                  24.0000000000];

  auto summ = Summary();
  summ.sum= 787.0000000000;
  summ.min= 21.0000000000;
  summ.max= 40.0000000000;
  summ.mean= 31.4800000000;
  summ.median= 32.0000000000;
  summ.var= 26.5933333333;
  summ.std_dev= 5.1568724372;
  summ.std_dev_pct= 16.3814245145;
  summ.median_abs_dev= 5.9304000000;
  summ.median_abs_dev_pct= 18.5325000000;
  summ.quartiles= tuple(28.0000000000, 32.0000000000, 34.0000000000);
  summ.iqr= 6.0000000000;

  check(samples, summ);
}

unittest
{
  // pois25lambda40
  auto samples = [42.0000000000,
                  50.0000000000,
                  42.0000000000,
                  46.0000000000,
                  34.0000000000,
                  45.0000000000,
                  34.0000000000,
                  49.0000000000,
                  39.0000000000,
                  28.0000000000,
                  40.0000000000,
                  35.0000000000,
                  37.0000000000,
                  39.0000000000,
                  46.0000000000,
                  44.0000000000,
                  32.0000000000,
                  45.0000000000,
                  42.0000000000,
                  37.0000000000,
                  48.0000000000,
                  42.0000000000,
                  33.0000000000,
                  42.0000000000,
                  48.0000000000];

  auto summ = Summary();
  summ.sum= 1019.0000000000;
  summ.min= 28.0000000000;
  summ.max= 50.0000000000;
  summ.mean= 40.7600000000;
  summ.median= 42.0000000000;
  summ.var= 34.4400000000;
  summ.std_dev= 5.8685603004;
  summ.std_dev_pct= 14.3978417577;
  summ.median_abs_dev= 5.9304000000;
  summ.median_abs_dev_pct= 14.1200000000;
  summ.quartiles= tuple(37.0000000000, 42.0000000000, 45.0000000000);
  summ.iqr= 8.0000000000;

  check(samples, summ);
}


unittest
{
  // pois25lambda50
  auto samples = [45.0000000000,
                  43.0000000000,
                  44.0000000000,
                  61.0000000000,
                  51.0000000000,
                  53.0000000000,
                  59.0000000000,
                  52.0000000000,
                  49.0000000000,
                  51.0000000000,
                  51.0000000000,
                  50.0000000000,
                  49.0000000000,
                  56.0000000000,
                  42.0000000000,
                  52.0000000000,
                  51.0000000000,
                  43.0000000000,
                  48.0000000000,
                  48.0000000000,
                  50.0000000000,
                  42.0000000000,
                  43.0000000000,
                  42.0000000000,
                  60.0000000000];

  auto summ = Summary();
  summ.sum= 1235.0000000000;
  summ.min= 42.0000000000;
  summ.max= 61.0000000000;
  summ.mean= 49.4000000000;
  summ.median= 50.0000000000;
  summ.var= 31.6666666667;
  summ.std_dev= 5.6273143387;
  summ.std_dev_pct= 11.3913245723;
  summ.median_abs_dev= 4.4478000000;
  summ.median_abs_dev_pct= 8.8956000000;
  summ.quartiles= tuple(44.0000000000, 50.0000000000, 52.0000000000);
  summ.iqr= 8.0000000000;

  check(samples, summ);
}


unittest
{
  // unif25
  auto samples = [99.0000000000,
                  55.0000000000,
                  92.0000000000,
                  79.0000000000,
                  14.0000000000,
                  2.0000000000,
                  33.0000000000,
                  49.0000000000,
                  3.0000000000,
                  32.0000000000,
                  84.0000000000,
                  59.0000000000,
                  22.0000000000,
                  86.0000000000,
                  76.0000000000,
                  31.0000000000,
                  29.0000000000,
                  11.0000000000,
                  41.0000000000,
                  53.0000000000,
                  45.0000000000,
                  44.0000000000,
                  98.0000000000,
                  98.0000000000,
                  7.0000000000];

  auto summ = Summary();
  summ.sum= 1242.0000000000;
  summ.min= 2.0000000000;
  summ.max= 99.0000000000;
  summ.mean= 49.6800000000;
  summ.median= 45.0000000000;
  summ.var= 1015.6433333333;
  summ.std_dev= 31.8691595957;
  summ.std_dev_pct= 64.1488719719;
  summ.median_abs_dev= 45.9606000000;
  summ.median_abs_dev_pct= 102.1346666667;
  summ.quartiles= tuple(29.0000000000, 45.0000000000, 79.0000000000);
  summ.iqr= 50.0000000000;

  check(samples, summ);
}

unittest
{
  assert([0.5, 3.2321, 1.5678].sum() == 5.2999);
}

unittest
{
  import std.stdio : writeln;

  // writeln(1e30 + 1.2);
  // writeln(1.2 + 1e30);

  // writeln(1e30 - 1.2);
  // writeln(1.2 - 1e30);


  assert([1e30, 1.2, -1e30].sum() == 1.2);
}
