This tutorial shows how to go from a single-agent simulation (Tutorial 01) to a
full **fleet-level forecast**. By the end you will be able to:
- build a heterogeneous cohort of delivery agents,
- run the cohort through an 8-hour shift,
- generate probabilistic forecasts of delivery events and battery state across
  the fleet.

We use the urban food delivery model throughout. If you haven't worked through
[01_core_engine_scaffold.md](01_core_engine_scaffold.md), start there — it
covers the `Entity`, `ModelBundle`, and `Engine` concepts that this tutorial
builds on.

## Load the model

The delivery model lives in a plain R script. Sourcing it gives you
`delivery_bundle()`, `delivery_schema()`, and the individual callback functions.
No package install required.


``` r
source("tutorials/model/urban_delivery.R")
```

## Build a heterogeneous cohort

A **cohort** is just a named list of `Entity` objects. Each agent starts its
shift with a different battery level, home zone, and starting state — exactly
the kind of heterogeneity you see in a real fleet.


``` r
set.seed(2026)

n_agents <- 20
shared_schema <- delivery_schema()

agents <- lapply(seq_len(n_agents), function(i) {
  Entity$new(
    id   = paste0("driver_", sprintf("%02d", i)),
    init = list(
      battery_pct   = runif(1, min = 50, max = 100),
      route_zone    = sample(c("urban", "suburban", "rural"), 1,
                             prob = c(0.55, 0.30, 0.15)),
      payload_kg    = 0,
      dispatch_mode = "idle"
    ),
    schema      = shared_schema,
    entity_type = "delivery_agent",
    time0       = 0
  )
})
names(agents) <- vapply(agents, function(e) e$id, character(1))
```

Quick sanity check — the fleet's starting battery distribution:


``` r
batteries <- vapply(agents, function(e) e$current$battery_pct, numeric(1))
summary(batteries)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>   50.27   61.30   68.81   69.91   78.15   95.55
```

## Single-agent run

Before running the full cohort, let's step through one agent to see the shape
of the output. The `Engine` is constructed once from the bundle and then reused
for every agent.


``` r
eng <- Engine$new(bundle = delivery_bundle())

out_single <- eng$run(agents[[1]], max_events = 500, return_observations = TRUE)
```

The result contains:
- `$events` — the authoritative event log (one row per realized event)
- `$observations` — whatever the `observe()` hook emitted
- `$entity` — the same entity object, now mutated to post-run state


``` r
nrow(out_single$events)
#> [1] 14
tail(out_single$observations, 5)
#>        time         event_type process_id route_zone battery_pct payload_kg
#> 9  6.273878 delivery_completed   delivery      urban    54.90422   2.758148
#> 10 6.710594     dispatch_check   dispatch      urban    54.71679   3.249756
#> 11 6.841524 delivery_completed   delivery      urban    52.48632   2.508905
#> 12 7.599790 delivery_completed   delivery      urban    47.54659   1.411589
#> 13 8.000000          end_shift  end_shift      urban    47.54659   1.411589
#>    dispatch_mode
#> 9     in_transit
#> 10      assigned
#> 11    in_transit
#> 12    in_transit
#> 13          idle
out_single$entity$state(c("battery_pct", "dispatch_mode"))
#> <flux_state>
#> $battery_pct
#> [1] 47.54659
#> 
#> $dispatch_mode
#> [1] "idle"
```

The final event should be `end_shift` — the model's terminal event. The battery
will be lower than it started, and the agent may have completed several
deliveries during the shift.

## Cohort simulation

`run_cohort()` runs the engine over every entity in the list, optionally with
multiple parameter draws (for uncertainty quantification) and multiple simulation
replicates per draw.


``` r
cohort_result <- run_cohort(
  eng,
  entities     = agents,
  n_param_draws = 1,
  n_sims       = 50,
  max_events   = 500,
  seed         = 42
)
```

The result is an indexed list of run outputs. `cohort_result$index` tells you
which entity/draw/sim each slot corresponds to.


``` r
head(cohort_result$index)
#>   entity_id param_draw_id sim_id run_id
#> 1 driver_01             1      1  run_1
#> 2 driver_01             1      2  run_2
#> 3 driver_01             1      3  run_3
#> 4 driver_01             1      4  run_4
#> 5 driver_01             1      5  run_5
#> 6 driver_01             1      6  run_6
```

## Forecasting

Now the real value of the ecosystem: `fluxForecast` takes the raw simulation
output and answers probabilistic questions about the future.

### `forecast()` — the entry point

`forecast()` wraps the cohort run into a forecast object that downstream
functions can query. It needs the engine, the entities, and the evaluation
times (the "horizon grid" at which we want predictions).


``` r
times <- seq(1, 8, by = 1)  # evaluate at hours 1 through 8

fc <- forecast(
  engine   = eng,
  entities = agents,
  times    = times,
  S        = 50,       # simulation draws per entity
  seed     = 42
)
#> Warning: Model schema omits 'alive'; deriving lifecycle status from
#> bundle$terminal_events.
```

### `event_prob()` — probability of a delivery event

"What is the probability that each agent completes at least one delivery by
hour *t*?"


``` r
ep <- event_prob(fc, event = "delivery_completed", times = times)
head(ep)
#> $spec
#> $spec$event
#> [1] "delivery_completed"
#> 
#> $spec$times
#> [1] 1 2 3 4 5 6 7 8
#> 
#> $spec$start_time
#> [1] 1
#> 
#> $spec$terminal_events
#> NULL
#> 
#> $spec$condition_on_events
#> NULL
#> 
#> $spec$by
#> [1] "run"
#> 
#> 
#> $cohort
#> $cohort$eligible_run_ids
#>    [1]    1    2    3    4    5    6    7    8    9   10   11   12   13   14
#>   [15]   15   16   17   18   19   20   21   22   23   24   25   26   27   28
#>   [29]   29   30   31   32   33   34   35   36   37   38   39   40   41   42
#>   [43]   43   44   45   46   47   48   49   50   51   52   53   54   55   56
#>   [57]   57   58   59   60   61   62   63   64   65   66   67   68   69   70
#>   [71]   71   72   73   74   75   76   77   78   79   80   81   82   83   84
#>   [85]   85   86   87   88   89   90   91   92   93   94   95   96   97   98
#>   [99]   99  100  101  102  103  104  105  106  107  108  109  110  111  112
#>  [113]  113  114  115  116  117  118  119  120  121  122  123  124  125  126
#>  [127]  127  128  129  130  131  132  133  134  135  136  137  138  139  140
#>  [141]  141  142  143  144  145  146  147  148  149  150  151  152  153  154
#>  [155]  155  156  157  158  159  160  161  162  163  164  165  166  167  168
#>  [169]  169  170  171  172  173  174  175  176  177  178  179  180  181  182
#>  [183]  183  184  185  186  187  188  189  190  191  192  193  194  195  196
#>  [197]  197  198  199  200  201  202  203  204  205  206  207  208  209  210
#>  [211]  211  212  213  214  215  216  217  218  219  220  221  222  223  224
#>  [225]  225  226  227  228  229  230  231  232  233  234  235  236  237  238
#>  [239]  239  240  241  242  243  244  245  246  247  248  249  250  251  252
#>  [253]  253  254  255  256  257  258  259  260  261  262  263  264  265  266
#>  [267]  267  268  269  270  271  272  273  274  275  276  277  278  279  280
#>  [281]  281  282  283  284  285  286  287  288  289  290  291  292  293  294
#>  [295]  295  296  297  298  299  300  301  302  303  304  305  306  307  308
#>  [309]  309  310  311  312  313  314  315  316  317  318  319  320  321  322
#>  [323]  323  324  325  326  327  328  329  330  331  332  333  334  335  336
#>  [337]  337  338  339  340  341  342  343  344  345  346  347  348  349  350
#>  [351]  351  352  353  354  355  356  357  358  359  360  361  362  363  364
#>  [365]  365  366  367  368  369  370  371  372  373  374  375  376  377  378
#>  [379]  379  380  381  382  383  384  385  386  387  388  389  390  391  392
#>  [393]  393  394  395  396  397  398  399  400  401  402  403  404  405  406
#>  [407]  407  408  409  410  411  412  413  414  415  416  417  418  419  420
#>  [421]  421  422  423  424  425  426  427  428  429  430  431  432  433  434
#>  [435]  435  436  437  438  439  440  441  442  443  444  445  446  447  448
#>  [449]  449  450  451  452  453  454  455  456  457  458  459  460  461  462
#>  [463]  463  464  465  466  467  468  469  470  471  472  473  474  475  476
#>  [477]  477  478  479  480  481  482  483  484  485  486  487  488  489  490
#>  [491]  491  492  493  494  495  496  497  498  499  500  501  502  503  504
#>  [505]  505  506  507  508  509  510  511  512  513  514  515  516  517  518
#>  [519]  519  520  521  522  523  524  525  526  527  528  529  530  531  532
#>  [533]  533  534  535  536  537  538  539  540  541  542  543  544  545  546
#>  [547]  547  548  549  550  551  552  553  554  555  556  557  558  559  560
#>  [561]  561  562  563  564  565  566  567  568  569  570  571  572  573  574
#>  [575]  575  576  577  578  579  580  581  582  583  584  585  586  587  588
#>  [589]  589  590  591  592  593  594  595  596  597  598  599  600  601  602
#>  [603]  603  604  605  606  607  608  609  610  611  612  613  614  615  616
#>  [617]  617  618  619  620  621  622  623  624  625  626  627  628  629  630
#>  [631]  631  632  633  634  635  636  637  638  639  640  641  642  643  644
#>  [645]  645  646  647  648  649  650  651  652  653  654  655  656  657  658
#>  [659]  659  660  661  662  663  664  665  666  667  668  669  670  671  672
#>  [673]  673  674  675  676  677  678  679  680  681  682  683  684  685  686
#>  [687]  687  688  689  690  691  692  693  694  695  696  697  698  699  700
#>  [701]  701  702  703  704  705  706  707  708  709  710  711  712  713  714
#>  [715]  715  716  717  718  719  720  721  722  723  724  725  726  727  728
#>  [729]  729  730  731  732  733  734  735  736  737  738  739  740  741  742
#>  [743]  743  744  745  746  747  748  749  750  751  752  753  754  755  756
#>  [757]  757  758  759  760  761  762  763  764  765  766  767  768  769  770
#>  [771]  771  772  773  774  775  776  777  778  779  780  781  782  783  784
#>  [785]  785  786  787  788  789  790  791  792  793  794  795  796  797  798
#>  [799]  799  800  801  802  803  804  805  806  807  808  809  810  811  812
#>  [813]  813  814  815  816  817  818  819  820  821  822  823  824  825  826
#>  [827]  827  828  829  830  831  832  833  834  835  836  837  838  839  840
#>  [841]  841  842  843  844  845  846  847  848  849  850  851  852  853  854
#>  [855]  855  856  857  858  859  860  861  862  863  864  865  866  867  868
#>  [869]  869  870  871  872  873  874  875  876  877  878  879  880  881  882
#>  [883]  883  884  885  886  887  888  889  890  891  892  893  894  895  896
#>  [897]  897  898  899  900  901  902  903  904  905  906  907  908  909  910
#>  [911]  911  912  913  914  915  916  917  918  919  920  921  922  923  924
#>  [925]  925  926  927  928  929  930  931  932  933  934  935  936  937  938
#>  [939]  939  940  941  942  943  944  945  946  947  948  949  950  951  952
#>  [953]  953  954  955  956  957  958  959  960  961  962  963  964  965  966
#>  [967]  967  968  969  970  971  972  973  974  975  976  977  978  979  980
#>  [981]  981  982  983  984  985  986  987  988  989  990  991  992  993  994
#>  [995]  995  996  997  998  999 1000
#> 
#> $cohort$n_eligible
#> [1] 1000
#> 
#> 
#> $result
#>   time n_eligible n_events event_prob  risk
#> 1    1       1000      242      0.242 0.242
#> 2    2       1000      587      0.587 0.587
#> 3    3       1000      795      0.795 0.795
#> 4    4       1000      902      0.902 0.902
#> 5    5       1000      945      0.945 0.945
#> 6    6       1000      970      0.970 0.970
#> 7    7       1000      986      0.986 0.986
#> 8    8       1000      996      0.996 0.996
#> 
#> $meta
#> list()
```

Each row gives an entity × time combination with the estimated probability. You
can think of this as an "event risk" curve — it starts near 0 at t=0 and
approaches 1 as the shift progresses (most agents do complete deliveries).

Agents starting with low battery tend to have lower delivery probability early
on:


``` r
# Compare the 5 lowest-battery agents vs the 5 highest
low_bat  <- names(sort(batteries))[1:5]
high_bat <- names(sort(batteries, decreasing = TRUE))[1:5]

ep_low  <- ep[ep$entity_id %in% low_bat & ep$time == 4, ]
#> Error in ep[ep$entity_id %in% low_bat & ep$time == 4, ]: incorrect number of dimensions
ep_high <- ep[ep$entity_id %in% high_bat & ep$time == 4, ]
#> Error in ep[ep$entity_id %in% high_bat & ep$time == 4, ]: incorrect number of dimensions

cat("Mean P(delivery by hour 4) — low battery group: ",
    round(mean(ep_low$prob), 3), "\n")
#> Error: object 'ep_low' not found
cat("Mean P(delivery by hour 4) — high battery group:",
    round(mean(ep_high$prob), 3), "\n")
#> Error: object 'ep_high' not found
```

### `state_summary()` — distribution of a state variable

"What does the battery distribution look like across the fleet at each hour?"


``` r
ss <- state_summary(fc, vars = "battery_pct", times = times)
#> Error: Unknown vars: battery_pct
head(ss)
#> Error: object 'ss' not found
```

This gives you quantiles (or other summary statistics) of `battery_pct` at each
evaluation time. As the shift progresses, the distribution shifts left — agents
drain their batteries at different rates depending on their dispatch/delivery
intensity.

### `draws()` — inspect raw trajectories

For a single agent, you can pull the underlying simulation draws to see the
stochastic spread:


``` r
dr <- draws(fc, var = "battery_pct", times = times)
#> Error: Unknown var(s) not stored in flux_forecast: battery_pct
# Filter to one agent
dr_one <- dr[dr$entity_id == "driver_01", ]
#> Error: object 'dr' not found
head(dr_one, 10)
#> Error: object 'dr_one' not found
```

Each row is one draw × one time point. You get the full distribution rather than
just a summary — useful for checking whether the forecast is well-behaved or if
there are pathological outliers.

## Varying model parameters

One of the design goals of the bundle architecture is that you can swap
parameters without changing any other code. Let's compare the default dispatch
rate against a slower fleet:


``` r
# Default: dispatch_rate_base = 0.7
eng_slow <- Engine$new(bundle = delivery_bundle(
  params = list(dispatch_rate_base = 0.3)
))

fc_slow <- forecast(
  engine   = eng_slow,
  entities = agents,
  times    = times,
  S        = 50,
  seed     = 42
)

ep_slow <- event_prob(fc_slow, event = "delivery_completed", times = times)
```

Compare mean fleet-wide delivery probability at hour 4:


``` r
cat("Default dispatch rate — P(delivery by hour 4):",
    round(mean(ep[ep$time == 4, "prob"]), 3), "\n")
#> Error in ep[ep$time == 4, "prob"]: incorrect number of dimensions
cat("Slow dispatch rate   — P(delivery by hour 4):",
    round(mean(ep_slow[ep_slow$time == 4, "prob"]), 3), "\n")
#> Error in ep_slow[ep_slow$time == 4, "prob"]: incorrect number of dimensions
```

The slower dispatch rate produces a flatter event probability curve — agents
receive fewer assignments, so fewer deliveries are completed by any given hour.
This is exactly the kind of "what if" scenario that fleet operators care about:
if demand drops (lower dispatch rate), how does delivery throughput change?

## Summary

| Concept | What you learned |
|---------|-----------------|
| `Entity` cohort | A named list of entities with heterogeneous starting state |
| `run_cohort()` | Batch simulation with parameter draws and replicates |
| `forecast()` | Wraps cohort output into a queryable forecast object |
| `event_prob()` | Probability of a named event by time *t* |
| `state_summary()` | Distribution of a state variable at each time point |
| `draws()` | Raw per-draw trajectories for detailed inspection |
| Parameter variation | Swap `delivery_bundle(params = ...)` to test scenarios |

**Next:** [04_decisions_policy.md](04_decisions_policy.md) — add decision points
and policies to the model, compare agent outcomes under different dispatch
strategies.
