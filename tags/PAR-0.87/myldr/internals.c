static void par_redo_stack (pTHX_ void *data) {
    PUSHEVAL((&cxstack[0]) , "", Nullgv);
}

XS(XS_Internals_PAR_CLEARSTACK) {
    dounwind(-1);
    SAVEDESTRUCTOR_X(par_redo_stack, 0);
}

XS(XS_Internals_PAR_BOOT) {
    GV* tmpgv;
    AV* tmpav;
    SV** svp;
    int i;
    int ok = 0;
    char *buf;

    TAINT;

    if (!(buf = par_getenv("PAR_INITIALIZED")) || buf[0] != '1' || buf[1] != '\0') {
        par_init_env();
    }

    if ((tmpgv = gv_fetchpv("ARGV", TRUE, SVt_PVAV))) {/* @ARGV */
        tmpav = GvAV(tmpgv);
        for (i = 1; i < options_count; i++) {
            svp = av_fetch(tmpav, i-1, 0);
            if (!svp) break;
            if (strcmp(fakeargv[i], SvPV_nolen(*svp))) break;
            ok++;
        }
        if (ok == options_count - 1) {
            for (i = 1; i < options_count; i++) {
                av_shift(tmpav);
            }
        }
    }

    if ((tmpgv = gv_fetchpv("\030",TRUE, SVt_PV))) {/* $^X */
#ifdef WIN32
        sv_setpv(GvSV(tmpgv),"perl.exe");
#else
        sv_setpv(GvSV(tmpgv),"perl");
#endif
        SvSETMAGIC(GvSV(tmpgv));
    }

    if ((tmpgv = gv_fetchpv("0", TRUE, SVt_PV))) {/* $0 */
        if ( ( stmpdir = par_getenv("PAR_TEMP") ) ) {
            sv_setpv(GvSV(tmpgv), fakeargv[0]);
        }
        else {
#ifdef HAS_PROCSELFEXE
            S_procself_val(aTHX_ GvSV(tmpgv), fakeargv[0]);
#else
#ifdef OS2
            sv_setpv(GvSV(tmpgv), os2_execname(aTHX));
#else
            sv_setpv(GvSV(tmpgv), fakeargv[0]);
#endif
#endif
        }
#if (PERL_REVISION == 5 && PERL_VERSION == 8 \
        && ( PERL_SUBVERSION >= 1 && PERL_SUBVERSION <= 5)) || \
    (PERL_REVISION == 5 && PERL_VERSION >= 9 && PERL_SUBVERSION <= 1)
        /* 5.8.1 and later perl versions no longer copies fakeargv, sigh */
        {
            char *p;
            STRLEN len = strlen( fakeargv[0] );
            New( 42, p, len+1, char );
            Copy( fakeargv[0], p, len, char );
            SvSETMAGIC(GvSV(tmpgv));
            Copy( p, fakeargv[0], len, char );
            fakeargv[0][len] = '\0';
            Safefree( p );
        }
        /*
#else
        SvSETMAGIC(GvSV(tmpgv));
        */
#endif
    }

    TAINT_NOT;

    /* PL_main_cv = PL_compcv; */
    PL_compcv = 0;

    /* create temporary PAR directory */
    stmpdir = par_getenv("PAR_TEMP");
    if ( stmpdir == NULL ) {
        stmpdir = par_mktmpdir( fakeargv );
#ifndef WIN32
        i = execvp(SvPV_nolen(GvSV(tmpgv)), fakeargv);
        croak("%s: execution of %s failed - aborting with %i.\n", fakeargv[0], SvPV_nolen(GvSV(tmpgv)), i);
        return;
#endif
    }

    i = PerlDir_mkdir(stmpdir, 0755);
    if ( (i != 0) && (i != EEXIST) && (i != -1) ) {
        croak("%s: creation of private temporary subdirectory %s failed - aborting with %i.\n", fakeargv[0], stmpdir, i);
        return;
    }
}

static void par_xs_init(pTHX)
{
    xs_init(aTHX);
    newXSproto("Internals::PAR::BOOT", XS_Internals_PAR_BOOT, "", "");
#ifdef PAR_CLEARSTACK
    newXSproto("Internals::PAR::CLEARSTACK", XS_Internals_PAR_CLEARSTACK, "", "");
#endif
}
