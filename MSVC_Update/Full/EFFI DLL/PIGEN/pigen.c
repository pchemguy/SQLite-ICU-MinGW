/*
** pigen.c
**
** Estimates pi using a Monte Carlo simulation.
*/

#include "pigen.h"


PIGEN_API double pi_approx(int n) {
    int i;
    int inside = 0;
    double x;
    double y;
    double radius_squared = (double)(RAND_MAX * RAND_MAX);

    if (n <= 0) {
        return 0.0;
    }

    for (i = 0; i < n; i++) {
        x = rand();
        y = rand();

        if (x * x + y * y < radius_squared) {
            inside++;
        }
    }

    return 4.0 * inside / n;
}