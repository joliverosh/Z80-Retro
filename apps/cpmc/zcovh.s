; zcovh.s - el comienzo de cada parte de ZCALC.OVL: ovl_entry(ovlop)
        .module zcovh
        .area   _OVL
        ld      a,(_ovlop)
        jp      _ovl_entry
