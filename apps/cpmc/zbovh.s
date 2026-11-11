; zbovh.s - el comienzo de la parte de ZBAS.OVL: ovl_entry(ovop)
        .module zbovh
        .area   _OVL
        ld      a,(_ovop)
        jp      _ovl_entry
