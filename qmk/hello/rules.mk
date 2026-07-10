VIA_ENABLE = yes
DEBOUNCE_TYPE = sym_defer_pk   # wait for DEBOUNCE ms of stable state before reporting -> coalesces a chattering switch's bounces into ONE press (fixes spacebar double-fire). Costs DEBOUNCE ms latency.
