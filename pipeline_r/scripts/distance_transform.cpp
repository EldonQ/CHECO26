#include <Rcpp.h>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

// Input and output use terra's row-major cell order.
// [[Rcpp::export]]
Rcpp::NumericVector exact_grid_distance(const Rcpp::NumericVector& feature,
                                         int rows, int cols,
                                         double dx, double dy) {
  if (rows < 1 || cols < 1 || feature.size() != R_xlen_t(rows) * cols ||
      !std::isfinite(dx) || !std::isfinite(dy) || dx <= 0 || dy <= 0) {
    Rcpp::stop("invalid grid for Euclidean distance");
  }
  const double infinity = std::numeric_limits<double>::infinity();
  Rcpp::NumericVector distance(feature.size(), infinity);
  std::vector<int> last(cols, -1);
  bool any_feature = false;

  // The two vertical passes give the exact squared distance within each column.
  for (int row = 0; row < rows; ++row) {
    const R_xlen_t offset = R_xlen_t(row) * cols;
    for (int col = 0; col < cols; ++col) {
      if (feature[offset + col] == 1) {
        last[col] = row;
        any_feature = true;
      }
      if (last[col] >= 0) {
        const double gap = (row - last[col]) * dy;
        distance[offset + col] = gap * gap;
      }
    }
  }
  if (!any_feature) Rcpp::stop("feature grid contains no cells with value 1");
  std::fill(last.begin(), last.end(), -1);
  for (int row = rows - 1; row >= 0; --row) {
    const R_xlen_t offset = R_xlen_t(row) * cols;
    for (int col = 0; col < cols; ++col) {
      if (feature[offset + col] == 1) last[col] = row;
      if (last[col] >= 0) {
        const double gap = (last[col] - row) * dy;
        distance[offset + col] = std::min(distance[offset + col], gap * gap);
      }
    }
  }

  // The lower envelope of the horizontal parabolas gives the exact 2-D result.
  const double dx2 = dx * dx;
  std::vector<int> sites(cols);
  std::vector<double> costs(cols), bounds(cols + 1);
  for (int row = 0; row < rows; ++row) {
    const R_xlen_t offset = R_xlen_t(row) * cols;
    int top = -1;
    for (int col = 0; col < cols; ++col) {
      const double value = distance[offset + col];
      if (!std::isfinite(value)) continue;
      double boundary = -infinity;
      while (top >= 0) {
        const double prior = sites[top];
        boundary = (value - costs[top]) / (2.0 * dx2 * (col - prior)) +
                   (col + prior) / 2.0;
        if (boundary > bounds[top]) break;
        --top;
      }
      ++top;
      sites[top] = col;
      costs[top] = value;
      bounds[top] = top == 0 ? -infinity : boundary;
      bounds[top + 1] = infinity;
    }
    int site = 0;
    for (int col = 0; col < cols; ++col) {
      while (bounds[site + 1] < col) ++site;
      const double gap = (col - sites[site]) * dx;
      distance[offset + col] = std::sqrt(costs[site] + gap * gap);
    }
    if (row % 64 == 0) Rcpp::checkUserInterrupt();
  }
  return distance;
}
