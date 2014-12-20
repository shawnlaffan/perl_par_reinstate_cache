static void par_redo_stack (pTHX_ void *data) {
#if PERL_VERSION > 10
    PUSHEVAL((&cxstack[0]) , "");
#else
    PUSHEVAL((&cxstack[0]) , "", Nullgv);
#endif
}

XS(XS_Internals_PAR_Reuseperl_BOOT) {
    GV* tmpgv;
    AV* tmpav;
    SV** svp;
    SV* tmpsv;
    int i;
    int ok = 0;
    char *buf;

    TAINT;

    if (!(buf = par_getenv("PAR_INITIALIZED")) || buf[0] != '1' || buf[1] != '\0') {
        /* FIXME check this */
        /*par_init_env();*/
    }

    TAINT_NOT;

    /* PL_main_cv = PL_compcv; */
    PL_compcv = 0;

    stmpdir = par_getenv("PAR_TEMP");
}

static void reuse_par_xs_init(pTHX)
{
    xs_init(aTHX);
    newXSproto("Internals::PAR::Reuseperl::BOOT", XS_Internals_PAR_Reuseperl_BOOT, "", "");
}
