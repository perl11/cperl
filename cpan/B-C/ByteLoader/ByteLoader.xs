/* This loads bytecode in .plc files starting with PLBC.
   Produced by the B::Bytecode compiler.

   It might also be useful for JIT or ASM compiled
   PLJC .plc files where a full PE/COFF or MACHO/ELF format is not
   supported nor wanted, jumps are not patched,
   or a full executable dump is not possible.
*/

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "byterun.h"

/* Something arbitary for a buffer size */
#define BYTELOADER_BUFFER 8096

int
bl_getc(struct byteloader_fdata *data)
{
    dTHX;
    if (SvCUR(data->datasv) <= (STRLEN)data->next_out) {
      int result;
      /* Run out of buffered data, so attempt to read some more */
      *(SvPV_nolen(data->datasv)) = '\0';
      SvCUR_set(data->datasv, 0);
      data->next_out = 0;
      result = FILTER_READ(data->idx + 1, data->datasv, BYTELOADER_BUFFER);

      /* Filter returned error, or we got EOF and no data, then return EOF.
	 Not sure if filter is allowed to return EOF and add data simultaneously
	 Think not, but will bullet proof against it. */
      if (result < 0 || SvCUR(data->datasv) == 0)
	return EOF;
      /* Else there must be at least one byte present, which is good enough */
    }

    return *((U8 *) SvPV_nolen(data->datasv) + data->next_out++);
}

int
bl_read(struct byteloader_fdata *data, char *buf, size_t size, size_t n)
{
    dTHX;
    char *start;
    STRLEN len;
    size_t wanted = size * n;

    start = SvPV(data->datasv, len);
    if (len < (data->next_out + wanted)) {
      int result;

      /* Shuffle data to start of buffer */
      len -= data->next_out;
      if (len) {
	memmove(start, start + data->next_out, len + 1);
      } else {
	*start = '\0';	/* Avoid call to memmove. */
      }
      SvCUR_set(data->datasv, len);
      data->next_out = 0;

      /* Attempt to read more data. */
      do {
	result = FILTER_READ(data->idx + 1, data->datasv, BYTELOADER_BUFFER);
	
	start = SvPV(data->datasv, len);
      } while (result > 0 && len < wanted);
      /* Loop while not (EOF || error) and short reads */

      /* If not enough data read, truncate copy */
      if (wanted > len)
	wanted = len;
    }

    if (wanted > 0) {
      memcpy(buf, start + data->next_out, wanted);
      data->next_out += wanted;
      wanted /= size;
    }
    return (int) wanted;
}

static I32
byteloader_filter(pTHX_ int idx, SV *buf_sv, int maxlen)
{
    OP *saveroot = PL_main_root;
    OP *savestart = PL_main_start;
    struct byteloader_state bstate;
    struct byteloader_fdata data;
    int len;
    (void)buf_sv;
    (void)maxlen;

    data.next_out = 0;
    data.datasv = FILTER_DATA(idx);
    /* [perl #86186] Using tell(DATA) within __DATA__ file buffer is broken on Win32:
       Source filters were changed with 5.14 to read DATA in textmode, so \r\n are
       changed to \n on Windows only in our binary data.
     */
#if (PERL_VERSION < 17) && (PERL_VERSION > 7)
    PerlIO_binmode(aTHX_ PL_RSFP, IoTYPE_RDONLY, O_BINARY, 0);
#endif
    data.idx = idx;

    bstate.bs_fdata = &data;
    bstate.bs_obj_list = Null(void**);
    bstate.bs_obj_list_fill = -1;
    bstate.u.bs_sv = Nullsv;
    bstate.bs_iv_overflows = 0;

/* KLUDGE */
    /*  byterun loads incrementally from DATA, jitrun might require the whole
	buffer at once. best via mmap */
    if (byterun(aTHX_ &bstate)
        && (len = SvCUR(data.datasv) - (STRLEN)data.next_out))
    {
	PerlIO_seek(PL_RSFP, -len, SEEK_CUR);
	PL_RSFP = NULL;
    }
    filter_del(byteloader_filter);

    if (PL_in_eval) {
        OP *o;

        PL_eval_start = PL_main_start;

        o = newSVOP(OP_CONST, 0, newSViv(1));
        PL_eval_root = newLISTOP(OP_LINESEQ, 0, PL_main_root, o);
        PL_main_root->op_next = o;
        PL_eval_root = newUNOP(OP_LEAVEEVAL, 0, PL_eval_root);
        o->op_next = PL_eval_root;

        PL_main_root = saveroot;
        PL_main_start = savestart;
    }
    /* Proof for [cperl #75] that newPROG() overwrites our main_start */
#if PERL_VERSION > 21 && defined(DEBUGGING)
    if (DEBUG_t_TEST_ && DEBUG_v_TEST_) {
      op_dump(PL_main_start);
      op_dump(PL_main_start->op_next);
    }
#endif
    return 0;
}

MODULE = ByteLoader		PACKAGE = ByteLoader

PROTOTYPES:	ENABLE

void
import(...)
  PREINIT:
    SV *sv = newSVpvn ("", 0);
  PPCODE:
    if (!sv)
      croak ("Could not allocate ByteLoader buffers");
    filter_add(byteloader_filter, sv);

void
unimport(...)
  PPCODE:
    filter_del(byteloader_filter);


# Local variables:
#   c-indent-level: 4
# End:
# vim: expandtab shiftwidth=4:
