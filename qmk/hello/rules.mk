VIA_ENABLE = yes
DEBOUNCE_TYPE = sym_eager_pk   # report the press on the FIRST edge, then lock that key out for DEBOUNCE ms to swallow chatter -> kills the spacebar double-fire WITHOUT dropping fast taps. (sym_defer_pk waited for DEBOUNCE ms of stable state and silently dropped any press held <DEBOUNCE ms.)
