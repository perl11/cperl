/* vim: ts=8 sw=4 expandtab:
 * ************************************************************************
 * This file is part of the Devel::NYTProf package.
 * See http://metacpan.org/release/Devel-NYTProf/
 * For Copyright see lib/Devel/NYTProf.pm
 * For contribution history see repository logs.
 * ************************************************************************
 */

#define PERL_NO_GET_CONTEXT                       /* we want efficiency */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#if defined(PERL_IMPLICIT_SYS) && !defined(NO_XSLOCKS)
#  ifndef fgets
#    define fgets PerlSIO_fgets
#  endif
#endif

#include "FileHandle.h"
#include "NYTProf.h"

#define NEED_newRV_noinc
#define NEED_sv_2pvbyte
#define NEED_my_snprintf
#include "ppport.h"

#ifdef HAS_ZLIB
#  include <zlib.h>
#endif

#define NYTP_FILE_STDIO         0
#define NYTP_FILE_DEFLATE       1
#define NYTP_FILE_INFLATE       2

/* to help find places in NYTProf.xs where we don't save/restore errno */
#if 0
#define ERRNO_PROBE errno=__LINE__
#else
#define ERRNO_PROBE (void)0
#endif

/* During profiling the large buffer collects the raw data until full.
 * Then flush_output zips it into the small buffer and writes it to disk.
 * A scale factor of ~90 makes the large buffer usually almost fill the small
 * one when zipped (so calls to flush_output() almost always trigger one fwrite()).
 * We use a lower number to save some memory as there's little performance
 * impact either way.
 */
#define NYTP_FILE_SMALL_BUFFER_SIZE   4096
#define NYTP_FILE_LARGE_BUFFER_SIZE   (NYTP_FILE_SMALL_BUFFER_SIZE * 40)

#ifdef HAS_ZLIB
#  define FILE_STATE(f)         ((f)->state)
#else
#  define FILE_STATE(f)         NYTP_FILE_STDIO
#endif

#if defined(PERL_IMPLICIT_CONTEXT) && ! defined(tTHX)
#  define tTHX PerlInterpreter*
#endif

struct NYTP_file_t {
    FILE *file;
#ifdef PERL_IMPLICIT_CONTEXT
    tTHX aTHX; /* on 5.8 and older, pTHX contains a "register" which is not
                  compatible with a struct def, so use something else */
#endif
#ifdef HAS_ZLIB
    unsigned char state;
    bool stdio_at_eof;
    bool zlib_at_eof;
    /* For input only, the position we are in large_buffer.  */
    unsigned int count;
    z_stream zs;
    unsigned char small_buffer[NYTP_FILE_SMALL_BUFFER_SIZE];
    unsigned char large_buffer[NYTP_FILE_LARGE_BUFFER_SIZE];
#endif
};

/* unlike dTHX which contains a function call, and therefore can never be
  optimized away, even if return value isn't used, the below will optimize away
  if NO_XSLOCKS is defined and PerlIO is not being used (i.e. native C lib
  IO is being used on Win32 )*/
#ifdef PERL_IMPLICIT_CONTEXT
#  define dNFTHX(x) dTHXa((x)->aTHX)
#else
#  define dNFTHX(x) dNOOP
#endif

/* XXX The proper return value would be Off_t */
long
NYTP_tell(NYTP_file file) {
    ERRNO_PROBE;

#ifdef HAS_ZLIB
    /* This has to work with compressed files as it's used in the croaking
       routine.  */
    if (FILE_STATE(file) != NYTP_FILE_STDIO) {
        return FILE_STATE(file) == NYTP_FILE_INFLATE
            ? file->zs.total_out : file->zs.total_in;
    }
#endif
    {
        dNFTHX(file);
        return (long)ftell(file->file);
    }
}

#ifdef HAS_ZLIB
const char *
NYTP_type_of_offset(NYTP_file file) {
    switch (FILE_STATE(file)) {
    case NYTP_FILE_STDIO:
        return "";
    case NYTP_FILE_DEFLATE:
        return " in compressed output data";
        break;
    case NYTP_FILE_INFLATE:
        return " in compressed input data";
        break;
    default:
        return Perl_form_nocontext(" in stream in unknown state %d",
                                   FILE_STATE(file));
    }
}
#endif

#ifdef HAS_ZLIB
#  define CROAK_IF_NOT_STDIO(file, where)           \
    STMT_START {                                    \
        if (FILE_STATE(file) != NYTP_FILE_STDIO) {  \
            compressed_io_croak((file), (where));   \
        }                                           \
    } STMT_END
#else
#  define CROAK_IF_NOT_STDIO(file, where)
#endif

#ifdef HAS_ZLIB
#ifdef HASATTRIBUTE_NORETURN
__attribute__noreturn__
#endif 
static void
compressed_io_croak(NYTP_file file, const char *function) {
    const char *what;

    switch (FILE_STATE(file)) {
    case NYTP_FILE_STDIO:
        what = "stdio";
        break;
    case NYTP_FILE_DEFLATE:
        what = "compressed output";
        break;
    case NYTP_FILE_INFLATE:
        what = "compressed input";
        break;
    default:
        croak("Can't use function %s() on a stream of type %d at offset %ld",
              function, FILE_STATE(file), NYTP_tell(file));
    }
    croak("Can't use function %s() on a %s stream at offset %ld", function,
          what, NYTP_tell(file));
}

void
NYTP_start_deflate(NYTP_file file, int compression_level) {
    int status;
    ERRNO_PROBE;

    CROAK_IF_NOT_STDIO(file, "NYTP_start_deflate");
    FILE_STATE(file) = NYTP_FILE_DEFLATE;
    file->zs.next_in = (Bytef *) file->large_buffer;
    file->zs.avail_in = 0;
    file->zs.next_out = (Bytef *) file->small_buffer;
    file->zs.avail_out = NYTP_FILE_SMALL_BUFFER_SIZE;
    file->zs.zalloc = (alloc_func) 0;
    file->zs.zfree = (free_func) 0;
    file->zs.opaque = 0;

    status = deflateInit2(&(file->zs), compression_level, Z_DEFLATED,
        15 /* windowBits */,
        9 /* memLevel */, Z_DEFAULT_STRATEGY);
    if (status != Z_OK) {
        croak("deflateInit2 failed, error %d (%s)", status, file->zs.msg);
    }
}

void
NYTP_start_inflate(NYTP_file file) {
    int status;
    ERRNO_PROBE;

    CROAK_IF_NOT_STDIO(file, "NYTP_start_inflate");
    FILE_STATE(file) = NYTP_FILE_INFLATE;

    file->zs.next_in = (Bytef *) file->small_buffer;
    file->zs.avail_in = 0;
    file->zs.next_out = (Bytef *) file->large_buffer;
    file->zs.avail_out = NYTP_FILE_LARGE_BUFFER_SIZE;
    file->zs.zalloc = (alloc_func) 0;
    file->zs.zfree = (free_func) 0;
    file->zs.opaque = 0;

    status = inflateInit2(&(file->zs), 15);
    if (status != Z_OK) {
        croak("inflateInit2 failed, error %d (%s)", status, file->zs.msg);
    }
}
#endif

NYTP_file
NYTP_open(const char *name, const char *mode) {
    dTHX;
    FILE *raw_file = fopen(name, mode);
    NYTP_file file;
    ERRNO_PROBE;

    if (!raw_file)
        return NULL;

    /* MS libc has 4096 as default, this is too slow for GB size profiling data */
    if (setvbuf(raw_file, NULL, _IOFBF, 16384)) {
        fclose(raw_file);
        return NULL;
    }
    Newx(file, 1, struct NYTP_file_t);
    file->file = raw_file;

#ifdef PERL_IMPLICIT_CONTEXT
    file->aTHX = aTHX;
#endif
#ifdef HAS_ZLIB
    file->state = NYTP_FILE_STDIO;
    file->count = 0;
    file->stdio_at_eof = FALSE;
    file->zlib_at_eof = FALSE;

    file->zs.msg = (char *)"[Oops. zlib hasn't updated this error string]";
#endif

    return file;
}

#ifdef HAS_ZLIB

static void
grab_input(NYTP_file ifile) {
    dNFTHX(ifile);
    ERRNO_PROBE;

    ifile->count = 0;
    ifile->zs.next_out = (Bytef *) ifile->large_buffer;
    ifile->zs.avail_out = NYTP_FILE_LARGE_BUFFER_SIZE;

#ifdef DEBUG_INFLATE
    fprintf(stderr, "grab_input enter\n");
#endif

    while (1) {
        int status;

        if (ifile->zs.avail_in == 0 && !ifile->stdio_at_eof) {
            size_t got = fread(ifile->small_buffer, 1,
                               NYTP_FILE_SMALL_BUFFER_SIZE, ifile->file);

            if (got == 0) {
                if (!feof(ifile->file)) {
                    int eno = errno;
                    croak("grab_input failed: %d (%s)", eno, strerror(eno));
                }
                ifile->stdio_at_eof = TRUE;
            }

            ifile->zs.avail_in = got;
            ifile->zs.next_in = (Bytef *) ifile->small_buffer;
        }

#ifdef DEBUG_INFLATE
        fprintf(stderr, "grab_input predef  next_in= %p avail_in= %08x\n"
                        "                   next_out=%p avail_out=%08x"
                " eof=%d,%d\n", ifile->zs.next_in, ifile->zs.avail_in,
                ifile->zs.next_out, ifile->zs.avail_out, ifile->stdio_at_eof,
                ifile->zlib_at_eof);
#endif

        status = inflate(&(ifile->zs), Z_NO_FLUSH);

#ifdef DEBUG_INFLATE
        fprintf(stderr, "grab_input postdef next_in= %p avail_in= %08x\n"
                        "                   next_out=%p avail_out=%08x "
                "status=%d\n", ifile->zs.next_in, ifile->zs.avail_in,
                ifile->zs.next_out, ifile->zs.avail_out, status);
#endif

        if (!(status == Z_OK || status == Z_STREAM_END)) {
            if (ifile->stdio_at_eof)
                croak("Profile data incomplete, inflate error %d (%s) at end of input file,"
                    " perhaps the process didn't exit cleanly or the file has been truncated "
                    " (refer to TROUBLESHOOTING in the documentation)\n",
                    status, ifile->zs.msg);
            croak("Error reading file: inflate failed, error %d (%s) at offset %ld in input file",
                  status, ifile->zs.msg, (long)ftell(ifile->file));
        }

        if (ifile->zs.avail_out == 0 || status == Z_STREAM_END) {
            if (status == Z_STREAM_END) {
                ifile->zlib_at_eof = TRUE;
            }
            return;
        }
    }
}

#endif


size_t
NYTP_read_unchecked(NYTP_file ifile, void *buffer, size_t len) {
    dNFTHX(ifile);
#ifdef HAS_ZLIB
    size_t result = 0;
#endif
    ERRNO_PROBE;
    if (FILE_STATE(ifile) == NYTP_FILE_STDIO) {
        return fread(buffer, 1, len, ifile->file);
    }
#ifdef HAS_ZLIB
    else if (FILE_STATE(ifile) != NYTP_FILE_INFLATE) {
        compressed_io_croak(ifile, "NYTP_read");
        return 0;
    }
    while (1) {
        unsigned char *p = ifile->large_buffer + ifile->count;
        int remaining = ((unsigned char *) ifile->zs.next_out) - p;

        if (remaining >= len) {
            Copy(p, buffer, len, unsigned char);
            ifile->count += len;
            result += len;
            return result;
        }
        Copy(p, buffer, remaining, unsigned char);
        ifile->count = NYTP_FILE_LARGE_BUFFER_SIZE;
        result += remaining;
        len -= remaining;
        buffer = (void *)(remaining + (char *)buffer);
        if (ifile->zlib_at_eof)
            return result;
        grab_input(ifile);
    }
#endif
}


size_t
NYTP_read(NYTP_file ifile, void *buffer, size_t len, const char *what) {
    size_t got = NYTP_read_unchecked(ifile, buffer, len);
    if (got != len) {
        croak("Profile format error whilst reading %s at %ld%s: expected %ld got %ld, %s (see TROUBLESHOOTING in docs)",
              what, NYTP_tell(ifile), NYTP_type_of_offset(ifile), (long)len, (long)got,
                (NYTP_eof(ifile)) ? "end of file" : NYTP_fstrerror(ifile));
    }
    return len;
}

/* This isn't exactly fgets. It will resize the buffer as needed, and returns
   a pointer to one beyond the read data (usually the terminating '\0'), or
   NULL if it hit error/EOF */

char *
NYTP_gets(NYTP_file ifile, char **buffer_p, size_t *len_p) {
    char *buffer = *buffer_p;
    size_t len = *len_p;
    size_t prev_len = 0;
    ERRNO_PROBE;

#ifdef HAS_ZLIB
    if (FILE_STATE(ifile) == NYTP_FILE_INFLATE) {
        while (1) {
            const unsigned char *const p = ifile->large_buffer + ifile->count;
            const unsigned int remaining = ((unsigned char *) ifile->zs.next_out) - p;
            unsigned char *const nl = (unsigned char *)memchr(p, '\n', remaining);
            size_t got;
            size_t want;
            size_t extra;

            if (nl) {
                want = nl + 1 - p;
                extra = want + 1; /* 1 more to add a \0 */
            } else {
                want = extra = remaining;
            }

            if (extra > len - prev_len) {
                prev_len = len;
                len += extra;
                buffer = (char *)saferealloc(buffer, len);
            }

            got = NYTP_read_unchecked(ifile, buffer + prev_len, want);
            if (got != want)
                croak("NYTP_gets unexpected short read. got %lu, expected %lu\n",
                      (unsigned long)got, (unsigned long)want);

            if (nl) {
                buffer[prev_len + want] = '\0';
                *buffer_p = buffer;
                *len_p = len;
                return buffer + prev_len + want;
            }
            if (ifile->zlib_at_eof) {
                *buffer_p = buffer;
                *len_p = len;
                return NULL;
            }
            grab_input(ifile);
        }
    }
#endif
    CROAK_IF_NOT_STDIO(ifile, "NYTP_gets");

    {
        dNFTHX(ifile);
        while(fgets(buffer + prev_len, (int)(len - prev_len), ifile->file)) {
            /* We know that there are no '\0' bytes in the part we've already
               read, so don't bother running strlen() over that part.  */
            char *end = buffer + prev_len + strlen(buffer + prev_len);
            if (end[-1] == '\n') {
                *buffer_p = buffer;
                *len_p = len;
                return end;
            }
            prev_len = len - 1; /* -1 to take off the '\0' at the end */
            len *= 2;
            buffer = (char *)saferealloc(buffer, len);
        }
    }
    *buffer_p = buffer;
    *len_p = len;
    return NULL;
}


#ifdef HAS_ZLIB
/* Cheat, by telling zlib about a reduced amount of available output space,
   such that our next write of the (slightly underused) output buffer will
   align the underlying file pointer back with the size of our output buffer
   (and hopefully the underlying OS block writes).  */
static void
sync_avail_out_to_ftell(NYTP_file ofile) {
    dNFTHX(ofile);
    const long result = ftell(ofile->file);
    const unsigned long where = result < 0 ? 0 : result;
    ERRNO_PROBE;
    ofile->zs.avail_out =
        NYTP_FILE_SMALL_BUFFER_SIZE - where % NYTP_FILE_SMALL_BUFFER_SIZE;
#ifdef DEBUG_DEFLATE
    fprintf(stderr, "sync_avail_out_to_ftell pos=%ld, avail_out=%lu\n",
            result, (unsigned long) ofile->zs.avail_out);
#endif
}

/* flush has values as described for "allowed flush values" in zlib.h  */
static void
flush_output(NYTP_file ofile, int flush) {
    dNFTHX(ofile);
    ERRNO_PROBE;

    ofile->zs.next_in = (Bytef *) ofile->large_buffer;

#ifdef DEBUG_DEFLATE
    fprintf(stderr, "flush_output enter   flush = %d\n", flush);
#endif
    while (1) {
        int status;
#ifdef DEBUG_DEFLATE
        fprintf(stderr, "flush_output predef  next_in= %p avail_in= %08x\n"
                        "                     next_out=%p avail_out=%08x"
                " flush=%d\n", ofile->zs.next_in, ofile->zs.avail_in,
                ofile->zs.next_out, ofile->zs.avail_out, flush);
#endif
        status = deflate(&(ofile->zs), flush);

        /* workaround for RT#50851 */
        if (status == Z_BUF_ERROR && flush != Z_NO_FLUSH
                && !ofile->zs.avail_in && ofile->zs.avail_out)
            status = Z_OK;

#ifdef DEBUG_DEFLATE
        fprintf(stderr, "flush_output postdef next_in= %p avail_in= %08x\n"
                        "                     next_out=%p avail_out=%08x "
                "status=%d\n", ofile->zs.next_in, ofile->zs.avail_in,
                ofile->zs.next_out, ofile->zs.avail_out, status);
#endif
      
        if (status == Z_OK || status == Z_STREAM_END) {
            if (ofile->zs.avail_out == 0 || flush != Z_NO_FLUSH) {
                int terminate
                    = ofile->zs.avail_in == 0 && ofile->zs.avail_out > 0;
                size_t avail = ((unsigned char *) ofile->zs.next_out)
                    - ofile->small_buffer;
                const unsigned char *where = ofile->small_buffer;

                while (avail > 0) {
                    size_t count = fwrite(where, 1, avail, ofile->file);

                    if (count > 0) {
                        where += count;
                        avail -= count;
                    } else {
                        int eno = errno;
                        croak("fwrite in flush error %d: %s", eno,
                              strerror(eno));
                    }
                }
                ofile->zs.next_out = (Bytef *) ofile->small_buffer;
                ofile->zs.avail_out = NYTP_FILE_SMALL_BUFFER_SIZE;
                if (terminate) {
                    ofile->zs.avail_in = 0;
                    if (flush == Z_SYNC_FLUSH) {
                        sync_avail_out_to_ftell(ofile);
                    }
                    return;
                }
            } else {
                ofile->zs.avail_in = 0;
                return;
            }
        } else {
            croak("deflate(%ld,%d) failed, error %d (%s) in pid %d",
                (long)ofile->zs.avail_in, flush, status, ofile->zs.msg, getpid());
        }
    }
}
#endif

size_t
NYTP_write(NYTP_file ofile, const void *buffer, size_t len) {
#ifdef HAS_ZLIB
    size_t result = 0;
#endif
    ERRNO_PROBE;

    if (FILE_STATE(ofile) == NYTP_FILE_STDIO) {
        /* fwrite with len==0 is problematic */
        /* http://www.opengroup.org/platform/resolutions/bwg98-007.html */
        if (len == 0)
            return len;
        {
            dNFTHX(ofile);
            if (fwrite(buffer, 1, len, ofile->file) < 1) {
                int eno = errno;
                croak("fwrite error %d writing %ld bytes to fd%d: %s",
                    eno, (long)len, fileno(ofile->file), strerror(eno));
            }
        }
        return len;
    }
#ifdef HAS_ZLIB
    else if (FILE_STATE(ofile) != NYTP_FILE_DEFLATE) {
        compressed_io_croak(ofile, "NYTP_write");
        return 0;
    }
    while (1) {
        int remaining = NYTP_FILE_LARGE_BUFFER_SIZE - ofile->zs.avail_in;
        unsigned char *p = ofile->large_buffer + ofile->zs.avail_in;

        if (remaining >= len) {
            Copy(buffer, p, len, unsigned char);
            ofile->zs.avail_in += len;
            result += len;
            return result;
        } else {
            /* Copy what we can, then flush the buffer. Lather, rinse, repeat.
             */
            Copy(buffer, p, remaining, unsigned char);
            ofile->zs.avail_in = NYTP_FILE_LARGE_BUFFER_SIZE;
            result += remaining;
            len -= remaining;
            buffer = (void *)(remaining + (char *)buffer);
            flush_output(ofile, Z_NO_FLUSH);
        }
    }
#endif
}

int
NYTP_printf(NYTP_file ofile, const char *format, ...) {
    int retval;
    va_list args;
    ERRNO_PROBE;

    CROAK_IF_NOT_STDIO(ofile, "NYTP_printf");

    va_start(args, format);
    {
        dNFTHX(ofile);
        retval = vfprintf(ofile->file, format, args);
    }
    va_end(args);

    return retval;
}

int
NYTP_flush(NYTP_file file) {
    ERRNO_PROBE;
#ifdef HAS_ZLIB
    if (FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        flush_output(file, Z_SYNC_FLUSH);
    }
#endif
    {
        dNFTHX(file);
        return fflush(file->file);
    }
}

int
NYTP_eof(NYTP_file ifile) {
    ERRNO_PROBE;
#ifdef HAS_ZLIB
    if (FILE_STATE(ifile) == NYTP_FILE_INFLATE) {
        return ifile->zlib_at_eof;
    }
#endif
    {
        dNFTHX(ifile);
        return feof(ifile->file);
    }
}

const char *
NYTP_fstrerror(NYTP_file file) {
#ifdef HAS_ZLIB
    if (FILE_STATE(file) == NYTP_FILE_DEFLATE || FILE_STATE(file) == NYTP_FILE_INFLATE) {
        return file->zs.msg;
    }
#endif
    {
        dNFTHX(file);
        return strerror(errno);
    }
}

int
NYTP_close(NYTP_file file, int discard) {
    FILE *raw_file = file->file;
    int result;
    dNFTHX(file);
    ERRNO_PROBE;

#ifdef HAS_ZLIB
    if (!discard && FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        const double ratio = file->zs.total_in / (double) file->zs.total_out;
        flush_output(file, Z_FINISH);
        fprintf(raw_file, "#\n"
                "# Compressed %lu bytes to %lu, ratio %f:1, data shrunk by %f%%\n",
                (long)file->zs.total_in, (long)file->zs.total_out, ratio,
                100 * (1 - 1 / ratio));
    }

    if (FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        int status = deflateEnd(&(file->zs));
        if (status != Z_OK) {
            if (discard && status == Z_DATA_ERROR) {
                /* deflateEnd returns Z_OK if success, Z_STREAM_ERROR if the
                   stream state was inconsistent, Z_DATA_ERROR if the stream
                   was freed prematurely (some input or output was discarded).
                */
            } else {
                croak("deflateEnd failed, error %d (%s) in %d", status,
                      file->zs.msg, getpid());
            }
        }
    }
    else if (FILE_STATE(file) == NYTP_FILE_INFLATE) {
        int err = inflateEnd(&(file->zs));
        if (err != Z_OK) {
            croak("inflateEnd failed, error %d (%s)", err, file->zs.msg);
        }
    }
#endif

    Safefree(file);

    result = ferror(raw_file) ? errno : 0;

    if (discard) {
        /* close the underlying fd first so any buffered data gets discarded
         * when fclose is called below */
        close(fileno(raw_file));
    }

    if (result || discard) {
        /* Something has already gone wrong, so try to preserve its error */
        fclose(raw_file);
        return result;
    }
    return fclose(raw_file) == 0 ? 0 : errno;
}


/* ====== Low-level element I/O functions ====== */

/**
 * Output an integer in bytes, optionally preceded by a tag. Use the special tag
 * NYTP_TAG_NO_TAG to suppress the tag output. A wrapper macro output_u32(fh, i)
 * does this for you.
 * "In bytes" means output the number in binary, using the least number of bytes
 * possible.  All numbers are positive. Use sign slot as a marker
 */
static size_t
output_tag_u32(NYTP_file file, unsigned char tag, U32 i)
{
    U8 buffer[6];
    U8 *p = buffer;

    if (tag != NYTP_TAG_NO_TAG)
        *p++ = tag;

    /* general case. handles all integers */
    if (i < 0x80) {                               /* < 8 bits */
        *p++ = (U8)i;
    }
    else if (i < 0x4000) {                        /* < 16 bits */
        *p++ = (U8)((i >> 8) | 0x80);
        *p++ = (U8)i;
    }
    else if (i < 0x200000) {                      /* < 24 bits */
        *p++ = (U8)((i >> 16) | 0xC0);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    else if (i < 0x10000000) {                    /* < 32 bits */
        *p++ = (U8)((i >> 24) | 0xE0);
        *p++ = (U8)(i >> 16);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    else {                                        /* need all the bytes. */
        *p++ = 0xFF;
        *p++ = (U8)(i >> 24);
        *p++ = (U8)(i >> 16);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    return NYTP_write(file, buffer, p - buffer);
}

static size_t
output_tag_i32(NYTP_file file, unsigned char tag, I32 i)
{
    return output_tag_u32(file, tag, *( (U32*) &i ) );
}

#define     output_u32(fh, i)   output_tag_u32((fh), NYTP_TAG_NO_TAG, (i))
#define     output_i32(fh, i)   output_tag_i32((fh), NYTP_TAG_NO_TAG, (i))


/**
 * Read an integer by decompressing the next 1 to 4 bytes of binary into a 32-
 * bit integer. See output_int() for the compression details.
 */
U32
read_u32(NYTP_file ifile)
{
    unsigned char d;
    U32 newint;

    NYTP_read(ifile, &d, sizeof(d), "integer prefix");

    if (d < 0x80) {                               /* < 8 bits */
        newint = d;
    }
    else {
        unsigned char buffer[4];
        unsigned char *p = buffer;
        unsigned int length;

        if (d < 0xC0) {                          /* < 16 bits */
            newint = d & 0x7F;
            length = 1;
        }
        else if (d < 0xE0) {                     /* < 24 bits */
            newint = d & 0x1F;
            length = 2;
        }
        else if (d < 0xFF) {                     /* < 32 bits */
            newint = d & 0xF;
            length = 3;
        }
        else { /* d == 0xFF */                   /* = 32 bits */
            newint = 0;
            length = 4;
        }
        NYTP_read(ifile, buffer, length, "integer");
        while (length--) {
            newint <<= 8;
            newint |= *p++;
        }
    }
    return newint;
}

I32
read_i32(NYTP_file ifile) {
    U32 u = read_u32(ifile);
    return *( (I32*)&u );
}


static size_t
output_str(NYTP_file file, const char *str, I32 len) {    /* negative len signifies utf8 */
    unsigned char tag = NYTP_TAG_STRING;
    size_t retval;
    size_t total;

    if (len < 0) {
        tag = NYTP_TAG_STRING_UTF8;
        len = -len;
    }

    total = retval = output_tag_u32(file, tag, len);
    if (retval <= 0)
        return retval;

    if (len) {
        total += retval = NYTP_write(file, str, len);
        if (retval <= 0)
            return retval;
    }

    return total;
}


/**
 * Output a double precision float via a simple binary write of the memory.
 * (Minor portbility issues are seen as less important than speed and space.)
 */
size_t
output_nv(NYTP_file file, NV nv)
{
    return NYTP_write(file, (unsigned char *)&nv, sizeof(NV));
}

/**
 * Read an NV by simple byte copy to memory
 */
NV
read_nv(NYTP_file ifile)
{
    NV nv;
    /* no error checking on the assumption that a later token read will
     * detect the error/eof condition
     */
    NYTP_read(ifile, (unsigned char *)&nv, sizeof(NV), "float");
    return nv;
}


/* ====== Higher-level protocol I/O functions ====== */

size_t
NYTP_write_header(NYTP_file ofile, U32 major, U32 minor)
{
    return NYTP_printf(ofile, "NYTProf %u %u\n", major, minor);
}

size_t
NYTP_write_comment(NYTP_file ofile, const char *format, ...) {
    size_t retval;
    size_t retval2;
    va_list args;
    ERRNO_PROBE;

    retval = NYTP_write(ofile, "#", 1);
    if (retval != 1)
        return retval;

    va_start(args, format);

    if(strEQc(format, "%s")) {
        const char * const s = va_arg(args, char*);
        STRLEN len = strlen(s);
        retval = NYTP_write(ofile, s, len);
    } else {
        CROAK_IF_NOT_STDIO(ofile, "NYTP_printf");
        {
            dNFTHX(ofile);
            retval = vfprintf(ofile->file, format, args);
        }
    }
    va_end(args);

    retval2 = NYTP_write(ofile, "\n", 1);
    if (retval2 != 1)
        return retval2;

    return retval + 2;
}

static size_t
NYTP_write_plain_kv(NYTP_file ofile, const char prefix,
                            const char *key, size_t key_len,
                            const char *value, size_t value_len)
{
    size_t total;
    size_t retval;

    total = retval = NYTP_write(ofile, &prefix, 1);
    if (retval != 1)
        return retval;

    total += retval = NYTP_write(ofile, key, key_len);
    if (retval != key_len)
        return retval;

    total += retval = NYTP_write(ofile, "=", 1);
    if (retval != 1)
        return retval;

    total += retval = NYTP_write(ofile, value, value_len);
    if (retval != value_len)
        return retval;

    total += retval = NYTP_write(ofile, "\n", 1);
    if (retval != 1)
        return retval;

    return total;
}

size_t
NYTP_write_attribute_string(NYTP_file ofile,
                            const char *key, size_t key_len,
                            const char *value, size_t value_len)
{
    return NYTP_write_plain_kv(ofile, ':', key, key_len, value, value_len);
}

#ifndef CHAR_BIT
#  define CHAR_BIT          8
#endif
#define LOG_2_OVER_LOG_10   0.30103

size_t
NYTP_write_attribute_unsigned(NYTP_file ofile, const char *key,
                              size_t key_len, unsigned long value)
{
    /* 3: 1 for rounding errors, 1 for the '\0'  */
    char buffer[(int)(sizeof (unsigned long) * CHAR_BIT * LOG_2_OVER_LOG_10 + 3)];
    const size_t len = my_snprintf(buffer, sizeof(buffer), "%lu", value);

    return NYTP_write_attribute_string(ofile, key, key_len, buffer, len);
}

size_t
NYTP_write_attribute_signed(NYTP_file ofile, const char *key,
                            size_t key_len, long value)
{
    /* 3: 1 for rounding errors, 1 for the sign, 1 for the '\0'  */
    char buffer[(int)(sizeof (long) * CHAR_BIT * LOG_2_OVER_LOG_10 + 3)];
    const size_t len = my_snprintf(buffer, sizeof(buffer), "%ld", value);

    return NYTP_write_attribute_string(ofile, key, key_len, buffer, len);
}

size_t
NYTP_write_attribute_nv(NYTP_file ofile, const char *key,
                            size_t key_len, NV value)
{
    char buffer[NV_DIG+20]; /* see Perl_sv_2pv_flags */
    const size_t len = my_snprintf(buffer, sizeof(buffer), "%" NVgf, value);

    return NYTP_write_attribute_string(ofile, key, key_len, buffer, len);
}

/* options */

size_t
NYTP_write_option_pv(NYTP_file ofile,
                    const char *key,
                    const char *value, size_t value_len)
{
    return NYTP_write_plain_kv(ofile, '!', key, strlen(key), value, value_len);
}

size_t
NYTP_write_option_iv(NYTP_file ofile, const char *key, IV value)
{
    /* 3: 1 for rounding errors, 1 for the sign, 1 for the '\0'  */
    char buffer[(int)(sizeof (IV) * CHAR_BIT * LOG_2_OVER_LOG_10 + 3)];
    const size_t len = my_snprintf(buffer, sizeof(buffer), "%" IVdf, value);

    return NYTP_write_option_pv(ofile, key, buffer, len);
}

/* other */

#ifdef HAS_ZLIB

size_t
NYTP_start_deflate_write_tag_comment(NYTP_file ofile, int compression_level) {
    const unsigned char tag = NYTP_TAG_START_DEFLATE;
    size_t total;
    size_t retval;

    total = retval = NYTP_write_comment(ofile, "Compressed at level %d with zlib %s",
                                        compression_level, zlibVersion());

    if (retval < 1)
        return retval;

    total += retval = NYTP_write(ofile, &tag, sizeof(tag));
    if (retval < 1)
        return retval;

    NYTP_start_deflate(ofile, compression_level);

    return total;
}

#endif

size_t
NYTP_write_process_start(NYTP_file ofile, U32 pid, U32 ppid,
                         NV time_of_day)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_PID_START, pid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, ppid);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, time_of_day);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_process_end(NYTP_file ofile, U32 pid, NV time_of_day)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_PID_END, pid);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, time_of_day);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_sawampersand(NYTP_file ofile, U32 fid, U32 line)
{
    size_t total;
    size_t retval;

    total = retval = NYTP_write_attribute_unsigned(ofile, STR_WITH_LEN("sawampersand_fid"),  fid);
    if (retval < 1)
        return retval;

    total += retval = NYTP_write_attribute_unsigned(ofile, STR_WITH_LEN("sawampersand_line"), line);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_new_fid(NYTP_file ofile, U32 id, U32 eval_fid,
                   U32 eval_line_num, U32 flags,
                   U32 size, U32 mtime,
                   const char *name, I32 len)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_NEW_FID, id);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, eval_fid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, eval_line_num);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, flags);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, size);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, mtime);
    if (retval < 1)
        return retval;

    total += retval = output_str(ofile, name, len);
    if (retval < 1)
        return retval;

    return total;
}

static size_t
write_time_common(NYTP_file ofile, unsigned char tag, I32 elapsed, U32 overflow,
                  U32 fid, U32 line)
{
    size_t total;
    size_t retval;

    if (overflow) {
        dNFTHX(ofile);
        /* XXX needs protocol change to output a new time-overflow tag */
        fprintf(stderr, "profile time overflow of %lu seconds discarded!\n",
            (unsigned long)overflow);
    }

    total = retval = output_tag_i32(ofile, tag, elapsed);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, fid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, line);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_time_block(NYTP_file ofile, I32 elapsed, U32 overflow,
    U32 fid, U32 line, U32 last_block_line, U32 last_sub_line)
{
    size_t total;
    size_t retval;

    total = retval = write_time_common(ofile, NYTP_TAG_TIME_BLOCK, elapsed, overflow,
                                       fid, line);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, last_block_line);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, last_sub_line);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_time_line(NYTP_file ofile, I32 elapsed, U32 overflow,
    U32 fid, U32 line)
{
    return write_time_common(ofile, NYTP_TAG_TIME_LINE, elapsed, overflow, fid, line);
}


size_t
NYTP_write_call_entry(NYTP_file ofile, U32 caller_fid, U32 caller_line)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_SUB_ENTRY, caller_fid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, caller_line);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_call_return(NYTP_file ofile, U32 prof_depth, const char *called_subname_pv,
    NV incl_subr_ticks, NV excl_subr_ticks)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_SUB_RETURN, prof_depth);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, incl_subr_ticks);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, excl_subr_ticks);
    if (retval < 1)
        return retval;

    if (!called_subname_pv)
        called_subname_pv = "(null)";
    total += retval = output_str(ofile, called_subname_pv, strlen(called_subname_pv));
    if (retval < 1)
        return retval;

    return total;
}


size_t
NYTP_write_sub_info(NYTP_file ofile, U32 fid,
                    const char *name, I32 len,
                    U32 first_line, U32 last_line)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_SUB_INFO, fid);
    if (retval < 1)
        return retval;

    total += retval = output_str(ofile, name, (I32)len);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, first_line);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, last_line);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_sub_callers(NYTP_file ofile, U32 fid, U32 line,
                       const char *caller_name, I32 caller_name_len,
                       U32 count, NV incl_rtime, NV excl_rtime,
                       NV reci_rtime, U32 depth,
                       const char *called_name, I32 called_name_len)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_SUB_CALLERS, fid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, line);
    if (retval < 1)
        return retval;

    total += retval = output_str(ofile, caller_name, caller_name_len);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, count);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, incl_rtime);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, excl_rtime);
    if (retval < 1)
        return retval;

    total += retval = output_nv(ofile, reci_rtime);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, depth);
    if (retval < 1)
        return retval;

    total += retval = output_str(ofile, called_name, called_name_len);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_src_line(NYTP_file ofile, U32 fid,
                    U32 line, const char *text, I32 text_len)
{
    size_t total;
    size_t retval;

    total = retval = output_tag_u32(ofile, NYTP_TAG_SRC_LINE, fid);
    if (retval < 1)
        return retval;

    total += retval = output_u32(ofile, line);
    if (retval < 1)
        return retval;

    total += retval = output_str(ofile, text, text_len);
    if (retval < 1)
        return retval;

    return total;
}

size_t
NYTP_write_discount(NYTP_file ofile)
{
    const unsigned char tag = NYTP_TAG_DISCOUNT;
    return NYTP_write(ofile, &tag, sizeof(tag));
}


MODULE = Devel::NYTProf::FileHandle     PACKAGE = Devel::NYTProf::FileHandle    PREFIX = NYTP_

PROTOTYPES: DISABLE

void
open(pathname, mode)
char *pathname
char *mode
    PREINIT:
        NYTP_file fh = NYTP_open(pathname, mode);
        SV *object;
    PPCODE:
        if(!fh)
            XSRETURN(0);
        object = newSV(0);
        sv_usepvn(object, (char *) fh, sizeof(struct NYTP_file_t));
        ST(0) = sv_bless(sv_2mortal(newRV_noinc(object)), gv_stashpvs("Devel::NYTProf::FileHandle", GV_ADD));
        XSRETURN(1);

int
DESTROY(handle)
NYTP_file handle
    ALIAS:
        close = 1
    PREINIT:
        SV *guts;
    CODE:
	guts = SvRV(ST(0));
        PERL_UNUSED_VAR(ix);
        RETVAL = NYTP_close(handle, 0);
        SvPV_set(guts, NULL);
        SvLEN_set(guts, 0);
    OUTPUT:
        RETVAL

size_t
write(handle, string)
NYTP_file handle
SV *string
    PREINIT:
        STRLEN len;
        char *p;
    CODE:
        p = SvPVbyte(string, len);
        RETVAL = NYTP_write(handle, p, len);
    OUTPUT:
        RETVAL

#ifdef HAS_ZLIB

void
NYTP_start_deflate(handle, compression_level = 6)
NYTP_file handle
int compression_level

void
NYTP_start_deflate_write_tag_comment(handle, compression_level = 6)
NYTP_file handle
int compression_level

#endif

size_t
NYTP_write_comment(handle, comment)
NYTP_file handle
char *comment
    CODE:
        RETVAL = NYTP_write_comment(handle, "%s", comment);
    OUTPUT:
        RETVAL

size_t
NYTP_write_attribute(handle, key, value)
NYTP_file handle
SV *key
SV *value
    PREINIT:
        STRLEN key_len;
        const char *const key_p = SvPVbyte(key, key_len);
        STRLEN value_len;
        const char *const value_p = SvPVbyte(value, value_len);
    CODE:
        RETVAL = NYTP_write_attribute_string(handle, key_p, key_len, value_p, value_len);
    OUTPUT:
        RETVAL

size_t
NYTP_write_option(handle, key, value)
NYTP_file handle
SV *key
SV *value
    PREINIT:
        STRLEN key_len;
        const char *const key_p = SvPVbyte(key, key_len);
        STRLEN value_len;
        const char *const value_p = SvPVbyte(value, value_len);
    CODE:
        RETVAL = NYTP_write_option_pv(handle, key_p, value_p, value_len);
    OUTPUT:
        RETVAL

size_t
NYTP_write_process_start(handle, pid, ppid, time_of_day)
NYTP_file handle
U32 pid
U32 ppid
NV time_of_day

size_t
NYTP_write_process_end(handle, pid, time_of_day)
NYTP_file handle
U32 pid
NV time_of_day

size_t
NYTP_write_new_fid(handle, id, eval_fid, eval_line_num, flags, size, mtime, name)
NYTP_file handle
U32 id
U32 eval_fid
int eval_line_num
U32 flags
U32 size
U32 mtime
SV *name
    PREINIT:
        STRLEN len;
        const char *const p = SvPV(name, len);
    CODE:
        RETVAL = NYTP_write_new_fid(handle, id, eval_fid, eval_line_num,
                                    flags, size, mtime, p,
                                    SvUTF8(name) ? -(I32)len : (I32)len );
    OUTPUT:
        RETVAL

size_t
NYTP_write_time_block(handle, elapsed, overflow, fid, line, last_block_line, last_sub_line)
NYTP_file handle
U32 elapsed
U32 overflow
U32 fid
U32 line
U32 last_block_line
U32 last_sub_line

size_t
NYTP_write_time_line(handle, elapsed, overflow, fid, line)
NYTP_file handle
U32 elapsed
U32 overflow
U32 fid
U32 line

size_t
NYTP_write_call_entry(handle, caller_fid, caller_line)
NYTP_file handle
U32 caller_fid
U32 caller_line

size_t
NYTP_write_call_return(handle, prof_depth, called_subname_pv, incl_subr_ticks, excl_subr_ticks)
NYTP_file handle
U32 prof_depth
const char *called_subname_pv
NV incl_subr_ticks
NV excl_subr_ticks

size_t
NYTP_write_sub_info(handle, fid, name, first_line, last_line)
NYTP_file handle
U32 fid
SV *name
U32 first_line
U32 last_line
    PREINIT:
        STRLEN len;
        const char *const p = SvPV(name, len);
    CODE:
        RETVAL = NYTP_write_sub_info(handle, fid,
                                     p, SvUTF8(name) ? -(I32)len : (I32)len,
                                     first_line, last_line);
    OUTPUT:
        RETVAL

size_t
NYTP_write_sub_callers(handle, fid, line, caller, count, incl_rtime, excl_rtime, reci_rtime, depth, called_sub)
NYTP_file handle
U32 fid
U32 line
SV *caller
U32 count
NV incl_rtime
NV excl_rtime
NV reci_rtime
U32 depth
SV *called_sub
    PREINIT:
        STRLEN caller_len;
        const char *const caller_p = SvPV(caller, caller_len);
        STRLEN called_len;
        const char *const called_p = SvPV(called_sub, called_len);
    CODE:
        RETVAL = NYTP_write_sub_callers(handle, fid, line, caller_p,
                                        SvUTF8(caller) ? -(I32)caller_len : (I32)caller_len,
                                        count, incl_rtime, excl_rtime,
                                        reci_rtime, depth, called_p,
                                        SvUTF8(called_sub) ? -(I32)called_len : (I32)called_len);
    OUTPUT:
        RETVAL

size_t
NYTP_write_src_line(handle, fid,  line, text)
NYTP_file handle
U32 fid
U32 line
SV *text
    PREINIT:
        STRLEN len;
        const char *const p = SvPV(text, len);
    CODE:
        RETVAL = NYTP_write_src_line(handle, fid, line,
                                     p, SvUTF8(text) ? -(I32)len : (I32)len);
    OUTPUT:
        RETVAL

size_t
NYTP_write_discount(handle)
NYTP_file handle

size_t
NYTP_write_header(handle, major, minor)
NYTP_file handle
U32 major
U32 minor

