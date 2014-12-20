/*
 * Copyright (c) 1997 Todd C. Miller <Todd.Miller@courtesan.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

#include "env.c"

char *par_findprog(char *prog, char *path) {
    char *p, filename[MAXPATHLEN];
    int proglen, plen;
    char *par_temp = par_getenv("PAR_TEMP");

#ifdef WIN32
    if ( GetModuleFileName(0, filename, MAXPATHLEN) ) {
        par_setenv("PAR_PROGNAME", filename);
        return strdup(filename);
    }
#endif

    /* Special case if prog contains '/' */
    if (strstr(prog, dir_sep)) {
        par_setenv("PAR_PROGNAME", prog);
        return(prog);
    }

    proglen = strlen(prog);
    p = strtok(path, path_sep);
    while ( p != NULL ) {
        if (*p == '\0') p = ".";

        if ( par_temp != NULL && ( strcmp(par_temp, p) == 0 ) ) {
            p = strtok(NULL, path_sep);
            continue;
        }

        plen = strlen(p);

        /* strip trailing '/' */
        while (p[plen-1] == *dir_sep) {
            p[--plen] = '\0';
        }

        if (plen + 1 + proglen >= MAXPATHLEN) {
            par_setenv("PAR_PROGNAME", prog);
            return(prog);
        }

        sprintf(filename, "%s%s%s", p, dir_sep, prog);
        if ((stat(filename, &PL_statbuf) == 0) && S_ISREG(PL_statbuf.st_mode) &&
            access(filename, X_OK) == 0) {
                par_setenv("PAR_PROGNAME", filename);
                return(strdup(filename));
        }
        p = strtok(NULL, path_sep);
    }

    par_setenv("PAR_PROGNAME", prog);
    return(prog);
}

char *par_basename (const char *name) {
    const char *base = name;
    const char *p;

    for (p = name; *p; p++) {
        if (*p == *dir_sep) base = p + 1;
    }

    return (char *)base;
}

char *par_dirname (const char *path) {
    static char bname[MAXPATHLEN];
    register const char *endp;

    /* Empty or NULL string gets treated as "." */
    if (path == NULL || *path == '\0') {
        return(strdup("."));
    }

    /* Strip trailing slashes */
    endp = path + strlen(path) - 1;
    while (endp > path && *endp == *dir_sep) endp--;

    /* Find the start of the dir */
    while (endp > path && *endp != *dir_sep) endp--;

    /* Either the dir is "/" or there are no slashes */
    if (endp == path) {
        if (*endp == *dir_sep) {
            return strdup(".");
        }
        else {
            return strdup(dir_sep);
        }
    } else {
        do {
            endp--;
        } while (endp > path && *endp == *dir_sep);
    }

    if (endp - path + 2 > sizeof(bname)) {
        return(NULL);
    }

    strncpy(bname, path, endp - path + 1);
    return(bname);
}

void par_init_env () {
    char par_clean[] = "__ENV_PAR_CLEAN__               \0";
    char *buf;

    par_unsetenv("PAR_INITIALIZED");
    par_unsetenv("PAR_SPAWNED");
    par_unsetenv("PAR_TEMP");
    par_unsetenv("PAR_CLEAN");
    par_unsetenv("PAR_DEBUG");
    par_unsetenv("PAR_CACHE");
    par_unsetenv("PAR_PROGNAME");
    par_unsetenv("PAR_ARGC");
    par_unsetenv("PAR_ARGV_0");

    if ( (buf = par_getenv("PAR_GLOBAL_DEBUG")) != NULL ) {
        par_setenv("PAR_DEBUG", buf);
    }

    if ( (buf = par_getenv("PAR_GLOBAL_TEMP")) != NULL ) {
        par_setenv("PAR_TEMP", buf);
    }
    else if ( (buf = par_getenv("PAR_GLOBAL_CLEAN")) != NULL ) {
        par_setenv("PAR_CLEAN", buf);
    }
    else {
        buf = par_clean + 12 + strlen("CLEAN");
        if (strncmp(buf, "PAR_CLEAN=", strlen("PAR_CLEAN=")) == 0) {
            par_setenv("PAR_CLEAN", buf + strlen("PAR_CLEAN="));
        }
    }

    par_setenv("PAR_INITIALIZED", "1");

    return;
}

int par_env_clean () {
    static int rv = -1;

    if (rv == -1) {
        char *buf = par_getenv("PAR_CLEAN");
        rv = ( ((buf == NULL) || (*buf == '\0') || (*buf == '0')) ? 0 : 1);
    }

    return rv;
}
