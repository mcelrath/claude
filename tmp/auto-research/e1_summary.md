# E1 results: cosine top-10 -> LLM re-rank

Samples: 18
Median LLM re-rank time: 3.91s
Total picks: 37  |  New (not in cosine top-3): 26
Samples where LLM picked NOTHING from cosine top-3: 3

## Per-sample table

label                          n_cand  n_pick  llm_t  new  rej  skip
------------------------------------------------------------------------------
braidinfer/text/0                   9       3   4.59    3    3  
braidinfer/text/1                  12       1   6.23    0    2  
braidinfer/edit/0                  15       3   9.29    3    3  
braidinfer/edit/1                  15       3   4.38    1    1  
braidinfer/read/0                   0       0   0.00    0    0  no-queries-in-v2
braidinfer/read/1                  15       3   3.08    2    2  
exterior-algebra/text/0            15       3   3.91    2    2  
exterior-algebra/text/1            15       3   3.52    2    2  
exterior-algebra/edit/0            15       3   3.36    2    2  
exterior-algebra/edit/1            15       3   3.72    2    2  
exterior-algebra/read/0            15       3   3.89    3    3  
exterior-algebra/read/1            15       3   3.82    2    2  
llama-cpp/text/0                   11       0   4.52    0    3  
llama-cpp/text/1                    6       0   3.06    0    3  
llama-cpp/edit/0                    6       3   2.41    2    2  
llama-cpp/edit/1                    3       0   1.55    0    3  
llama-cpp/read/0                   10       0   8.62    0    3  
llama-cpp/read/1                   15       3   4.63    2    2  

Columns:
  n_cand = pooled cosine candidates fed to LLM (dedup, cap 15)
  n_pick = RELEVANT verdicts in LLM output (cap 3)
  new    = picks NOT present in pooled cosine top-3
  rej    = pooled cosine top-3 entries the LLM did NOT pick