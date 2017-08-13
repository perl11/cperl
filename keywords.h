/* ex: set ro ft=c: -*- mode: c; buffer-read-only: t -*-
 *
 *    keywords.h
 *
 *    Copyright (C) 1994, 1995, 1996, 1997, 1999, 2000, 2001, 2002, 2005,
 *    2006, 2007 by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 * !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
 * This file is built by regen/keywords.pl from its data.
 * Any changes made here will be lost!
 */

#define KEY_NULL		0
#define KEY___FILE__		1
#define KEY___LINE__		2
#define KEY___PACKAGE__		3
#define KEY___DATA__		4
#define KEY___END__		5
#define KEY___SUB__		6
#define KEY_my			7
#define KEY_our			8
#define KEY_state		9
#define KEY_AUTOLOAD		10
#define KEY_BEGIN		11
#define KEY_UNITCHECK		12
#define KEY_DESTROY		13
#define KEY_END			14
#define KEY_INIT		15
#define KEY_CHECK		16
#define KEY_abs			17
#define KEY_accept		18
#define KEY_alarm		19
#define KEY_and			20
#define KEY_atan2		21
#define KEY_bind		22
#define KEY_binmode		23
#define KEY_bless		24
#define KEY_break		25
#define KEY_caller		26
#define KEY_chdir		27
#define KEY_chmod		28
#define KEY_chomp		29
#define KEY_chop		30
#define KEY_chown		31
#define KEY_chr			32
#define KEY_chroot		33
#define KEY_class		34
#define KEY_close		35
#define KEY_closedir		36
#define KEY_cmp			37
#define KEY_connect		38
#define KEY_continue		39
#define KEY_cos			40
#define KEY_crypt		41
#define KEY_dbmclose		42
#define KEY_dbmopen		43
#define KEY_default		44
#define KEY_defined		45
#define KEY_delete		46
#define KEY_die			47
#define KEY_do			48
#define KEY_dump		49
#define KEY_each		50
#define KEY_else		51
#define KEY_elsif		52
#define KEY_endgrent		53
#define KEY_endhostent		54
#define KEY_endnetent		55
#define KEY_endprotoent		56
#define KEY_endpwent		57
#define KEY_endservent		58
#define KEY_eof			59
#define KEY_eq			60
#define KEY_eval		61
#define KEY_evalbytes		62
#define KEY_exec		63
#define KEY_exists		64
#define KEY_exit		65
#define KEY_exp			66
#define KEY_fc			67
#define KEY_fcntl		68
#define KEY_fileno		69
#define KEY_flock		70
#define KEY_for			71
#define KEY_foreach		72
#define KEY_fork		73
#define KEY_format		74
#define KEY_formline		75
#define KEY_ge			76
#define KEY_getc		77
#define KEY_getgrent		78
#define KEY_getgrgid		79
#define KEY_getgrnam		80
#define KEY_gethostbyaddr	81
#define KEY_gethostbyname	82
#define KEY_gethostent		83
#define KEY_getlogin		84
#define KEY_getnetbyaddr	85
#define KEY_getnetbyname	86
#define KEY_getnetent		87
#define KEY_getpeername		88
#define KEY_getpgrp		89
#define KEY_getppid		90
#define KEY_getpriority		91
#define KEY_getprotobyname	92
#define KEY_getprotobynumber	93
#define KEY_getprotoent		94
#define KEY_getpwent		95
#define KEY_getpwnam		96
#define KEY_getpwuid		97
#define KEY_getservbyname	98
#define KEY_getservbyport	99
#define KEY_getservent		100
#define KEY_getsockname		101
#define KEY_getsockopt		102
#define KEY_given		103
#define KEY_glob		104
#define KEY_gmtime		105
#define KEY_goto		106
#define KEY_grep		107
#define KEY_gt			108
#define KEY_has			109
#define KEY_hex			110
#define KEY_if			111
#define KEY_index		112
#define KEY_int			113
#define KEY_ioctl		114
#define KEY_join		115
#define KEY_keys		116
#define KEY_kill		117
#define KEY_last		118
#define KEY_lc			119
#define KEY_lcfirst		120
#define KEY_le			121
#define KEY_length		122
#define KEY_link		123
#define KEY_listen		124
#define KEY_local		125
#define KEY_localtime		126
#define KEY_lock		127
#define KEY_log			128
#define KEY_lstat		129
#define KEY_lt			130
#define KEY_m			131
#define KEY_map			132
#define KEY_method		133
#define KEY_mkdir		134
#define KEY_msgctl		135
#define KEY_msgget		136
#define KEY_msgrcv		137
#define KEY_msgsnd		138
#define KEY_multi		139
#define KEY_ne			140
#define KEY_next		141
#define KEY_no			142
#define KEY_not			143
#define KEY_oct			144
#define KEY_open		145
#define KEY_opendir		146
#define KEY_or			147
#define KEY_ord			148
#define KEY_pack		149
#define KEY_package		150
#define KEY_pipe		151
#define KEY_pop			152
#define KEY_pos			153
#define KEY_print		154
#define KEY_printf		155
#define KEY_prototype		156
#define KEY_push		157
#define KEY_q			158
#define KEY_qq			159
#define KEY_qr			160
#define KEY_quotemeta		161
#define KEY_qw			162
#define KEY_qx			163
#define KEY_rand		164
#define KEY_read		165
#define KEY_readdir		166
#define KEY_readline		167
#define KEY_readlink		168
#define KEY_readpipe		169
#define KEY_recv		170
#define KEY_redo		171
#define KEY_ref			172
#define KEY_rename		173
#define KEY_require		174
#define KEY_reset		175
#define KEY_return		176
#define KEY_reverse		177
#define KEY_rewinddir		178
#define KEY_rindex		179
#define KEY_rmdir		180
#define KEY_role		181
#define KEY_s			182
#define KEY_say			183
#define KEY_scalar		184
#define KEY_seek		185
#define KEY_seekdir		186
#define KEY_select		187
#define KEY_semctl		188
#define KEY_semget		189
#define KEY_semop		190
#define KEY_send		191
#define KEY_setgrent		192
#define KEY_sethostent		193
#define KEY_setnetent		194
#define KEY_setpgrp		195
#define KEY_setpriority		196
#define KEY_setprotoent		197
#define KEY_setpwent		198
#define KEY_setservent		199
#define KEY_setsockopt		200
#define KEY_shift		201
#define KEY_shmctl		202
#define KEY_shmget		203
#define KEY_shmread		204
#define KEY_shmwrite		205
#define KEY_shutdown		206
#define KEY_sin			207
#define KEY_sleep		208
#define KEY_socket		209
#define KEY_socketpair		210
#define KEY_sort		211
#define KEY_splice		212
#define KEY_split		213
#define KEY_sprintf		214
#define KEY_sqrt		215
#define KEY_srand		216
#define KEY_stat		217
#define KEY_study		218
#define KEY_sub			219
#define KEY_substr		220
#define KEY_symlink		221
#define KEY_syscall		222
#define KEY_sysopen		223
#define KEY_sysread		224
#define KEY_sysseek		225
#define KEY_system		226
#define KEY_syswrite		227
#define KEY_tell		228
#define KEY_telldir		229
#define KEY_tie			230
#define KEY_tied		231
#define KEY_time		232
#define KEY_times		233
#define KEY_tr			234
#define KEY_truncate		235
#define KEY_uc			236
#define KEY_ucfirst		237
#define KEY_umask		238
#define KEY_undef		239
#define KEY_unless		240
#define KEY_unlink		241
#define KEY_unpack		242
#define KEY_unshift		243
#define KEY_untie		244
#define KEY_until		245
#define KEY_use			246
#define KEY_utime		247
#define KEY_values		248
#define KEY_vec			249
#define KEY_wait		250
#define KEY_waitpid		251
#define KEY_wantarray		252
#define KEY_warn		253
#define KEY_when		254
#define KEY_while		255
#define KEY_write		256
#define KEY_x			257
#define KEY_xor			258
#define KEY_y			259

/* Generated from:
 * 077e5a14bb04d2dcfaddcab0c5a9c7141f04d51e5a4261d295a9845c07a2cde5 regen/keywords.pl
 * ex: set ro: */
