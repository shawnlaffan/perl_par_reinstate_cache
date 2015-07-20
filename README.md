perl_par_reinstate_cache
========================

NOT THE OFFICIAL PAR REPO.

Its start point is a snapshot of the svn repo at revision 1528.

This was for work on re-extracting deleted cache files
after some process has cleaned up most of the temp files but
not all.

PAR calls otherwise failed in such cases.  

The official PAR repo is at https://www.openfoundry.org/svn/par/

The issue was fixed in PAR::Packer 1.026, with the  actual fix in PAR 1.010.  See https://rt.cpan.org/Ticket/Display.html?id=101800
