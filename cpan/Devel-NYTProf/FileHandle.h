/* vim: ts=8 sw=4 expandtab:
 * ************************************************************************
 * This file is part of the Devel::NYTProf package.
 * Copyright 2008 Adam J. Kaplan, The New York Times Company.
 * Copyright 2008 Tim Bunce, Ireland.
 * Released under the same terms as Perl 5.8
 * See http://metacpan.org/release/Devel-NYTProf/
 *
 * Contributors:
 * Adam Kaplan, akaplan at nytimes.com
 * Tim Bunce, http://www.tim.bunce.name and http://blog.timbunce.org
 * Steve Peters, steve at fisharerojo.org
 *
 * ************************************************************************
 */

/* Arguably this header is naughty, as it's not self contained, because it
   assumes that stdlib.h has already been included (via perl.h)  */

#if defined(PERL_IMPLICIT_SYS) && !defined(NO_XSLOCKS)
/* on Win32 XSUB.h redirects stdio to PerlIO, interp context is then required */
#  define NYTP_IO_dTHX dTHX
#  define NYTP_IO_NEEDS_THX
#else
#  define NYTP_IO_dTHX dNOOP
#endif

typedef struct NYTP_file_t *NYTP_file;

void NYTP_start_deflate(NYTP_file file, int compression_level);
void NYTP_start_inflate(NYTP_file file);

NYTP_file NYTP_open(const char *name, const char *mode);
char *NYTP_gets(NYTP_file ifile, char **buffer, size_t *len);
size_t NYTP_read_unchecked(NYTP_file ifile, void *buffer, size_t len);
size_t NYTP_read(NYTP_file ifile, void *buffer, size_t len, const char *what);
size_t NYTP_write(NYTP_file ofile, const void *buffer, size_t len);
int NYTP_scanf(NYTP_file ifile, const char *format, ...);
int NYTP_printf(NYTP_file ofile, const char *format, ...);
int NYTP_flush(NYTP_file file);
int NYTP_eof(NYTP_file ifile);
long NYTP_tell(NYTP_file file);
int NYTP_close(NYTP_file file, int discard);

const char *NYTP_fstrerror(NYTP_file file);
#ifdef HAS_ZLIB
const char *NYTP_type_of_offset(NYTP_file file);
#else
#  define NYTP_type_of_offset(file) ""
#endif

#define NYTP_TAG_NO_TAG          '\0'   /* Used as a flag to mean "no tag" */
#define NYTP_TAG_ATTRIBUTE       ':'    /* :name=value\n */
#define NYTP_TAG_OPTION          '!'    /* !name=value\n */
#define NYTP_TAG_COMMENT         '#'    /* till newline */
#define NYTP_TAG_TIME_BLOCK      '*'
#define NYTP_TAG_TIME_LINE       '+'
#define NYTP_TAG_DISCOUNT        '-'
#define NYTP_TAG_NEW_FID         '@'
#define NYTP_TAG_SRC_LINE        'S'    /* fid, line, str */
#define NYTP_TAG_SUB_INFO        's'
#define NYTP_TAG_SUB_CALLERS     'c'
#define NYTP_TAG_PID_START       'P'
#define NYTP_TAG_PID_END         'p'
#define NYTP_TAG_STRING          '\'' 
#define NYTP_TAG_STRING_UTF8     '"' 
#define NYTP_TAG_START_DEFLATE   'z' 
#define NYTP_TAG_SUB_ENTRY       '>'
#define NYTP_TAG_SUB_RETURN      '<'
/* also add new items to nytp_tax_index below */

typedef enum {      /* XXX keep in sync with various *_callback structures */
    nytp_no_tag,
    nytp_version,   /* Not actually a tag, but needed by the perl callback */
    nytp_attribute,
    nytp_option,
    nytp_comment,
    nytp_time_block,
    nytp_time_line,
    nytp_discount,
    nytp_new_fid,
    nytp_src_line,
    nytp_sub_info,
    nytp_sub_callers,
    nytp_pid_start,
    nytp_pid_end,
    nytp_string,
    nytp_string_utf8,
    nytp_start_deflate,
    nytp_sub_entry,
    nytp_sub_return,
    nytp_tag_max /* keep last */
} nytp_tax_index;

void NYTProf_croak_if_not_stdio(NYTP_file file, const char *function);

size_t NYTP_write_header(NYTP_file ofile, U32 major, U32 minor);
size_t NYTP_write_comment(NYTP_file ofile, const char *format, ...);
size_t NYTP_write_attribute_string(NYTP_file ofile,
                                   const char *key, size_t key_len,
                                   const char *value, size_t value_len);
size_t NYTP_write_attribute_signed(NYTP_file ofile, const char *key,
                                   size_t key_len, long value);
size_t NYTP_write_attribute_unsigned(NYTP_file ofile, const char *key,
                                     size_t key_len, unsigned long value);
size_t NYTP_write_attribute_nv(NYTP_file ofile, const char *key,
                                     size_t key_len, NV value);
size_t NYTP_write_option_pv(NYTP_file ofile, const char *key,
                                    const char *value, size_t value_len);
size_t NYTP_write_option_iv(NYTP_file ofile, const char *key, IV value);
size_t NYTP_start_deflate_write_tag_comment(NYTP_file ofile, int compression_level);
size_t NYTP_write_process_start(NYTP_file ofile, U32 pid, U32 ppid, NV time_of_day);
size_t NYTP_write_process_end(NYTP_file ofile, U32 pid, NV time_of_day);
size_t NYTP_write_sawampersand(NYTP_file ofile, U32 fid, U32 line);
size_t NYTP_write_new_fid(NYTP_file ofile, U32 id, U32 eval_fid, U32 eval_line_num,
                        U32 flags, U32 size, U32 mtime, const char *name, I32 len);
size_t NYTP_write_time_block(NYTP_file ofile, I32 elapsed, U32 overflow,
                        U32 fid, U32 line, U32 last_block_line, U32 last_sub_line);
size_t NYTP_write_time_line(NYTP_file ofile, I32 elapsed, U32 overflow,
                        U32 fid, U32 line);
size_t NYTP_write_sub_info(NYTP_file ofile, U32 fid, const char *name, I32 len,
                        U32 first_line, U32 last_line);
size_t NYTP_write_sub_callers(NYTP_file ofile, U32 fid, U32 line,
                        const char *caller_name, I32 caller_name_len,
                        U32 count, NV incl_rtime, NV excl_rtime,
                        NV reci_rtime, U32 depth,
                        const char *called_name, I32 called_name_len);
size_t NYTP_write_src_line(NYTP_file ofile, U32 fid,
                        U32 line, const char *text, I32 text_len);
size_t NYTP_write_discount(NYTP_file ofile);
size_t NYTP_write_call_entry(NYTP_file ofile, U32 caller_fid, U32 caller_line);
size_t NYTP_write_call_return(NYTP_file ofile, U32 prof_depth, const char *called_subname_pv,
                        NV incl_subr_ticks, NV excl_subr_ticks);


/* XXX
 * On the write-side the functions above encapsulate the data format.
 * On the read-side we've not got that far yet (and there's less need).
 */
U32 read_u32(NYTP_file ifile);
I32 read_i32(NYTP_file ifile);
NV  read_nv(NYTP_file ifile);

