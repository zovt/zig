const io = @import("std").io;

// TODO: import paths relative to package root when running tests on a specific file in the package
const adler32 = @import("./adler32.zig").adler32;
const crc32 = @import("./crc32.zig").crc32;

const ENOUGH_LENS = 852;
const ENOUGH_DISTS = 592;
const ENOUGH = ENOUGH_LENS + ENOUGH_DISTS;

pub enum inflate_mode {
    HEAD,       /* i: waiting for magic header */
    FLAGS,      /* i: waiting for method and flags (gzip) */
    TIME,       /* i: waiting for modification time (gzip) */
    OS,         /* i: waiting for extra flags and operating system (gzip) */
    EXLEN,      /* i: waiting for extra length (gzip) */
    EXTRA,      /* i: waiting for extra bytes (gzip) */
    NAME,       /* i: waiting for end of file name (gzip) */
    COMMENT,    /* i: waiting for end of comment (gzip) */
    HCRC,       /* i: waiting for header crc (gzip) */
    DICTID,     /* i: waiting for dictionary check value */
    DICT,       /* waiting for inflateSetDictionary() call */
        TYPE,       /* i: waiting for type bits, including last-flag bit */
        TYPEDO,     /* i: same, but skip check to exit inflate on new block */
        STORED,     /* i: waiting for stored size (length and complement) */
        COPY_,      /* i/o: same as COPY below, but only first time in */
        COPY,       /* i/o: waiting for input or output to copy stored block */
        TABLE,      /* i: waiting for dynamic block table lengths */
        LENLENS,    /* i: waiting for code length code lengths */
        CODELENS,   /* i: waiting for length/lit and distance code lengths */
            LEN_,       /* i: same as LEN below, but only first time in */
            LEN,        /* i: waiting for length/lit/eob code */
            LENEXT,     /* i: waiting for length extra bits */
            DIST,       /* i: waiting for distance code */
            DISTEXT,    /* i: waiting for distance extra bits */
            MATCH,      /* o: waiting for output space to copy string */
            LIT,        /* o: waiting for output space to write literal */
    CHECK,      /* i: waiting for 32-bit check value */
    LENGTH,     /* i: waiting for 32-bit length (gzip) */
    DONE,       /* finished check, done -- remain here until reset */
    BAD,        /* got a data error -- remain here until reset */
    MEM,        /* got an inflate() memory error -- remain here until reset */
    SYNC,       /* looking for synchronization bytes to restart inflate() */
}


pub struct code {
    op: u8,           /* operation, extra bits, table bits */
    bits: u8,         /* bits in this part of the code */
    val: u16,         /* offset in table or code value */
}

pub struct InflateState {
    mode: inflate_mode,     /* current inflate mode */
    last: bool,             /* true if processing last block */
    wrap: u8,               /* bit 0 true for zlib, bit 1 true for gzip */
    havedict: bool,         /* true if dictionary provided */
    flags: u32,             /* gzip header method and flags (0 if zlib) */
    dmax: u32,              /* zlib header max distance (INFLATE_STRICT) */
    check: u32,             /* protected copy of check value */
    total: u32,             /* protected copy of output count */
    head: ?&gz_header,      /* where to save gzip header information */
        /* sliding window */
    wbits: u32,             /* log base 2 of requested window size */
    wsize: u32,             /* window size or zero if not using window */
    whave: u32,             /* valid bytes in the window */
    wnext: u32,             /* window write index */
    window: [WINDOW_SIZE]u8,/* sliding window, if needed */
        /* bit accumulator */
    hold: u32,              /* input bit accumulator */
    bits: u32,              /* number of bits in "in" */
        /* for string and stored block copying */
    length: u32,            /* literal or length of data to copy */
    offset: u32,            /* distance back to copy string from */
        /* for table and code decoding */
    extra: u32,             /* extra bits needed */
        /* fixed and dynamic code tables */
    lencode: &const code,   /* starting table for length/literal codes */
    distcode: &const code,  /* starting table for distance codes */
    lenbits: u32,           /* index bits for lencode */
    distbits: u32,          /* index bits for distcode */
        /* dynamic table building */
    ncode: u32,             /* number of code length code lengths */
    nlen: u32,              /* number of length code lengths */
    ndist: u32,             /* number of distance code lengths */
    have: u32,              /* number of code lengths in lens[] */
    next: &code,            /* next available space in codes[] */
    lens: [320]u16,         /* temporary storage for code lengths */
    work: [288]u16,         /* work area for code table building */
    codes: [ENOUGH]code,    /* space for code tables */
    sane: bool,             /* if false, allow invalid distance too far */
    back: i32,              /* bits back of last unprocessed length/lit */
    was: u32,               /* initial length of match */
}

struct gz_header {
    text: bool,      /* true if compressed data believed to be text */
    time: u32,       /* modification time */
    xflags: u32,     /* extra flags (not used when writing a gzip file) */
    os: u32,         /* operating system */
    extra: &u8,      /* pointer to extra field or Z_NULL if none */
    extra_len: u32,  /* extra field length (valid if extra != Z_NULL) */
    extra_max: u32,  /* space at extra (only when reading header) */
    name: &u8,       /* pointer to zero-terminated file name or Z_NULL */
    name_max: u32,   /* space at name (only when reading header) */
    comment: &u8,    /* pointer to zero-terminated comment or Z_NULL */
    comm_max: u32,   /* space at comment (only when reading header) */
    hcrc: bool,      /* true if there was or will be a header crc */
    done: bool,      /* true when done reading gzip header (not used
                        when writing a gzip file) */
}

pub struct z_stream {
    next_in: ?&const u8,  /* next input byte */
    avail_in: u32,       /* number of bytes available at next_in */
    total_in: u32,       /* total number of input bytes read so far */

    next_out: ?&u8,      /* next output byte should be put there */
    avail_out: u32,      /* remaining free space at next_out */
    total_out: u32,      /* total number of bytes output so far */

    msg: []u8,           /* last error message, NULL if no error */

    data_type: u32,      /* best guess about the data type: binary or text */
    adler: u32,          /* adler32 value of the uncompressed data */

    state: InflateState, /* "not visible by applications" */
}

// this is the maximum allowed window size
const WINDOW_SIZE = 1 << 15;
const Z_DEFLATED = 8;

pub fn inflateInit(strm: &z_stream) {
  @memset(strm, 0, @sizeof(z_stream));
  inflateReset(strm);
}
pub fn inflateReset(strm: &z_stream) {
  var state = &strm.state;
  state.wsize = 0;
  state.whave = 0;
  state.wnext = 0;
  strm.total_in = 0;
  strm.total_out = 0;
  state.total = 0;
  strm.msg = "";
  if (state.wrap != 0) {
    /* to support ill-conceived Java test suite */
    strm.adler = state.wrap & 1;
  }
  state.mode = inflate_mode.HEAD;
  state.last = false;
  state.havedict = false;
  state.dmax = 32768;
  state.head = null;
  state.hold = 0;
  state.bits = 0;
  state.lencode = &state.codes[0];
  state.distcode = &state.codes[0];
  state.next = &state.codes[0];
  state.sane = true;
  state.back = -1;
}

error NullOutBuffer;
error NullInBuffer;
error CorruptState;

/* permutation of code lengths */
const order = []u16{
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
};

/* #define PULLBYTE() \
    do { \
        if (have == 0) goto inf_leave; \
        have--; \
        hold += (unsigned long)(*next++) << bits; \
        bits += 8; \
    } while (0)
*/
/* #define NEEDBITS(n) \
    do { \
        while (bits < (unsigned)(n)) \
            PULLBYTE(); \
    } while (0)
*/
/*
while (bits < n) {
  if (have == 0) goto inf_leave;
  have -= 1;
  hold += u32(*next) << bits;
  next += 1;
  bits += 8;
}
*/


fn BITS(hold: u32, n: u32) -> u32 {
    return hold & ((1 << n) - 1);
}
pub fn inflate(strm: &z_stream) -> %void {
  var state = &strm.state;

  var next: []u8 = undefined;      /* next input */
  var put: &u8 = undefined;        /* next output */
  // var have: u32 = undefined; now: next.len      /* available input and output */
  var left: u32 = undefined;       /* available input and output */
  var hold: u32 = undefined;       /* bit buffer */
  var bits: u32 = undefined;       /* bits in bit buffer */
  var in: isize = undefined;       /* save starting available input and output */
  var out: isize = undefined;      /* save starting available input and output */
  var copy: u32 = undefined;       /* number of stored or match bytes to copy */
  var from: &u8 = undefined;       /* where to copy match bytes from */
  var here: code = undefined;      /* current decoding table entry */
  var last: code = undefined;      /* parent table entry */
  var len: u32 = undefined;        /* length to copy for repeats, bits to drop */
  var ret: %void = void{};         /* return code */
  var hbuf: [4]u8 = undefined;     /* buffer for gzip header crc calculation */

  put = strm.next_out ?? return error.NullOutBuffer;
  left = strm.avail_out;
  next = if (strm.avail_in == 0) {
    []u8{}
  } else {
    // TODO: shouldn't have to cast to isize
    (strm.next_in ?? return error.NullInBuffer)[0...isize(strm.avail_in)]
  };
  hold = state.hold;
  bits = state.bits;

  if (state.mode == inflate_mode.TYPE) state.mode = inflate_mode.TYPEDO;      /* skip check */

  in = next.len;
  out = isize(left);
  while (true) {
    switch (state.mode) {
      HEAD => {
        if (state.wrap == 0) {
          state.mode = inflate_mode.TYPEDO;
          continue;
        }
        while (bits < 16) {
          // TODO: goto
          //if (next.len == 0) goto inf_leave;
          hold += u32(next[0]) << bits;
          next = next[1...];
          bits += 8;
        }
        if (state.wrap & 2 != 0 && hold == 0x8b1f) {  /* gzip header */
          state.check = crc32(0, "");
          hbuf[0] = u8(hold & 0xff);
          hbuf[1] = u8((hold >> 8) & 0xff);
          state.check = crc32(state.check, hbuf[0...2]);
          hold = 0;
          bits = 0;
          state.mode = inflate_mode.FLAGS;
          continue;
        }
        state.flags = 0;           /* expect zlib header */
        if (const head ?= state.head) {
          head.done = true; // -1;
        }
        /* check if zlib header allowed */
        if (state.wrap & 1 == 0 ||
            ((BITS(hold, 8) << 8) + (hold >> 8)) % 31 != 0) {
          strm.msg = "incorrect header check";
          state.mode = inflate_mode.BAD;
          continue;
        }
        if (BITS(hold, 4) != Z_DEFLATED) {
          strm.msg = "unknown compression method";
          state.mode = inflate_mode.BAD;
          continue;
        }
        hold >>= 4;
        bits -= 4;
        len = BITS(hold, 4) + 8;
        if (state.wbits == 0) {
          state.wbits = len;
        } else if (len > state.wbits) {
          strm.msg = "invalid window size";
          state.mode = inflate_mode.BAD;
          continue;
        }
        state.dmax = 1 << len;
        state.check = adler32(0, "");
        strm.adler = state.check;
        state.mode = if (hold & 0x200 != 0) inflate_mode.DICTID else inflate_mode.TYPE;
        hold = 0;
        bits = 0;
      },
      /*
        case inflate_mode.FLAGS:
            NEEDBITS(16);
            state.flags = (int)(hold);
            if ((state.flags & 0xff) != Z_DEFLATED) {
                strm.msg = (char *)"unknown compression method";
                state.mode = inflate_mode.BAD;
                continue;
            }
            if (state.flags & 0xe000) {
                strm.msg = (char *)"unknown header flags set";
                state.mode = inflate_mode.BAD;
                continue;
            }
            if (state.head != Z_NULL)
                state.head.text = (int)((hold >> 8) & 1);
            if (state.flags & 0x0200) {
                hbuf[0] = u8(hold & 0xff);
                hbuf[1] = u8((hold >> 8) & 0xff);
                state.check = crc32(state.check, hbuf[0...2]);
            }
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.TIME;
        case inflate_mode.TIME:
            NEEDBITS(32);
            if (state.head != Z_NULL)
                state.head.time = hold;
            if (state.flags & 0x0200) CRC4(state.check, hold);
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.OS;
        case inflate_mode.OS:
            NEEDBITS(16);
            if (state.head != Z_NULL) {
                state.head.xflags = (int)(hold & 0xff);
                state.head.os = (int)(hold >> 8);
            }
            if (state.flags & 0x0200) {
                hbuf[0] = u8(hold & 0xff);
                hbuf[1] = u8((hold >> 8) & 0xff);
                state.check = crc32(state.check, hbuf[0...2]);
            }
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.EXLEN;
        case inflate_mode.EXLEN:
            if (state.flags & 0x0400) {
                NEEDBITS(16);
                state.length = (unsigned)(hold);
                if (state.head != Z_NULL)
                    state.head.extra_len = (unsigned)hold;
                if (state.flags & 0x0200) {
                    hbuf[0] = u8(hold & 0xff);
                    hbuf[1] = u8((hold >> 8) & 0xff);
                    state.check = crc32(state.check, hbuf[0...2]);
                }
                hold = 0;
                bits = 0;
            }
            else if (state.head != Z_NULL)
                state.head.extra = Z_NULL;
            state.mode = inflate_mode.EXTRA;
        case inflate_mode.EXTRA:
            if (state.flags & 0x0400) {
                copy = state.length;
                if (copy > have) copy = have;
                if (copy) {
                    if (state.head != Z_NULL &&
                        state.head.extra != Z_NULL) {
                        len = state.head.extra_len - state.length;
                        zmemcpy(state.head.extra + len, next,
                                len + copy > state.head.extra_max ?
                                state.head.extra_max - len : copy);
                    }
                    if (state.flags & 0x0200)
                        state.check = crc32(state.check, next, copy);
                    have -= copy;
                    next += copy;
                    state.length -= copy;
                }
                if (state.length) goto inf_leave;
            }
            state.length = 0;
            state.mode = inflate_mode.NAME;
        case inflate_mode.NAME:
            if (state.flags & 0x0800) {
                if (have == 0) goto inf_leave;
                copy = 0;
                do {
                    len = (unsigned)(next[copy++]);
                    if (state.head != Z_NULL &&
                            state.head.name != Z_NULL &&
                            state.length < state.head.name_max)
                        state.head.name[state.length++] = len;
                } while (len && copy < have);
                if (state.flags & 0x0200)
                    state.check = crc32(state.check, next, copy);
                have -= copy;
                next += copy;
                if (len) goto inf_leave;
            }
            else if (state.head != Z_NULL)
                state.head.name = Z_NULL;
            state.length = 0;
            state.mode = inflate_mode.COMMENT;
        case inflate_mode.COMMENT:
            if (state.flags & 0x1000) {
                if (have == 0) goto inf_leave;
                copy = 0;
                do {
                    len = (unsigned)(next[copy++]);
                    if (state.head != Z_NULL &&
                            state.head.comment != Z_NULL &&
                            state.length < state.head.comm_max)
                        state.head.comment[state.length++] = len;
                } while (len && copy < have);
                if (state.flags & 0x0200)
                    state.check = crc32(state.check, next, copy);
                have -= copy;
                next += copy;
                if (len) goto inf_leave;
            }
            else if (state.head != Z_NULL)
                state.head.comment = Z_NULL;
            state.mode = inflate_mode.HCRC;
        case inflate_mode.HCRC:
            if (state.flags & 0x0200) {
                NEEDBITS(16);
                if (hold != (state.check & 0xffff)) {
                    strm.msg = (char *)"header crc mismatch";
                    state.mode = inflate_mode.BAD;
                    continue;
                }
                hold = 0;
                bits = 0;
            }
            if (state.head != Z_NULL) {
                state.head.hcrc = (int)((state.flags >> 9) & 1);
                state.head.done = true; // 1;
            }
            strm.adler = state.check = crc32(0L, Z_NULL, 0);
            state.mode = inflate_mode.TYPE;
            continue;
        case inflate_mode.DICTID:
            NEEDBITS(32);
            strm.adler = state.check = ZSWAP32(hold);
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.DICT;
        case inflate_mode.DICT:
            if (state.havedict == 0) {
                RESTORE();
                return Z_NEED_DICT;
            }
            strm.adler = state.check = adler32(0L, Z_NULL, 0);
            state.mode = inflate_mode.TYPE;
        case inflate_mode.TYPE:
            if (flush == Z_BLOCK || flush == Z_TREES) goto inf_leave;
        case inflate_mode.TYPEDO:
            if (state.last) {
                BYTEBITS();
                state.mode = inflate_mode.CHECK;
                continue;
            }
            NEEDBITS(3);
            state.last = BITS(hold, 1);
            hold >>= 1;
            bits -= 1;
            switch (BITS(hold, 2)) {
            case 0:                             /* stored block */
                state.mode = inflate_mode.STORED;
                continue;
            case 1:                             /* fixed block */
                fixedtables(state);
                state.mode = inflate_mode.LEN_;             /* decode codes */
                if (flush == Z_TREES) {
                    hold >>= 2;
                    bits -= 2;
                    goto inf_leave;
                }
                continue;
            case 2:                             /* dynamic block */
                state.mode = inflate_mode.TABLE;
                continue;
            case 3:
                strm.msg = (char *)"invalid block type";
                state.mode = inflate_mode.BAD;
            }
            hold >>= 2;
            bits -= 2;
            continue;
        case inflate_mode.STORED:
            BYTEBITS();                         /* go to byte boundary */
            NEEDBITS(32);
            if ((hold & 0xffff) != ((hold >> 16) ^ 0xffff)) {
                strm.msg = (char *)"invalid stored block lengths";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.length = (unsigned)hold & 0xffff;
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.COPY_;
            if (flush == Z_TREES) goto inf_leave;
        case inflate_mode.COPY_:
            state.mode = inflate_mode.COPY;
        case inflate_mode.COPY:
            copy = state.length;
            if (copy) {
                if (copy > have) copy = have;
                if (copy > left) copy = left;
                if (copy == 0) goto inf_leave;
                zmemcpy(put, next, copy);
                have -= copy;
                next += copy;
                left -= copy;
                put += copy;
                state.length -= copy;
                continue;
            }
            state.mode = inflate_mode.TYPE;
            continue;
        case inflate_mode.TABLE:
            NEEDBITS(14);
            state.nlen = BITS(hold, 5) + 257;
            hold >>= 5;
            bits -= 5;
            state.ndist = BITS(hold, 5) + 1;
            hold >>= 5;
            bits -= 5;
            state.ncode = BITS(hold, 4) + 4;
            hold >>= 4;
            bits -= 4;
            if (state.nlen > 286 || state.ndist > 30) {
                strm.msg = (char *)"too many length or distance symbols";
                state.mode = BAD;
                break;
            }
            state.have = 0;
            state.mode = inflate_mode.LENLENS;
        case inflate_mode.LENLENS:
            while (state.have < state.ncode) {
                NEEDBITS(3);
                state.lens[order[state.have++]] = (unsigned short)BITS(hold, 3);
                hold >>= 3;
                bits -= 3;
            }
            while (state.have < 19)
                state.lens[order[state.have++]] = 0;
            state.next = state.codes;
            state.lencode = (const code FAR *)(state.next);
            state.lenbits = 7;
            ret = inflate_table(CODES, state.lens, 19, &(state.next),
                                &(state.lenbits), state.work);
            if (ret) {
                strm.msg = (char *)"invalid code lengths set";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.have = 0;
            state.mode = inflate_mode.CODELENS;
        case inflate_mode.CODELENS:
            while (state.have < state.nlen + state.ndist) {
                for (;;) {
                    here = state.lencode[BITS(hold, state.lenbits)];
                    if ((unsigned)(here.bits) <= bits) break;
                    PULLBYTE();
                }
                if (here.val < 16) {
                    hold >>= here.bits;
                    bits -= here.bits;
                    state.lens[state.have++] = here.val;
                }
                else {
                    if (here.val == 16) {
                        NEEDBITS(here.bits + 2);
                        hold >>= here.bits;
                        bits -= here.bits;
                        if (state.have == 0) {
                            strm.msg = (char *)"invalid bit length repeat";
                            state.mode = inflate_mode.BAD;
                            continue;
                        }
                        len = state.lens[state.have - 1];
                        copy = 3 + BITS(hold, 2);
                        hold >>= 2;
                        bits -= 2;
                    }
                    else if (here.val == 17) {
                        NEEDBITS(here.bits + 3);
                        hold >>= here.bits;
                        bits -= here.bits;
                        len = 0;
                        copy = 3 + BITS(hold, 3);
                        hold >>= 3;
                        bits -= 3;
                    }
                    else {
                        NEEDBITS(here.bits + 7);
                        hold >>= here.bits;
                        bits -= here.bits;
                        len = 0;
                        copy = 11 + BITS(hold, 7);
                        hold >>= 7;
                        bits -= 7;
                    }
                    if (state.have + copy > state.nlen + state.ndist) {
                        strm.msg = (char *)"invalid bit length repeat";
                        state.mode = inflate_mode.BAD;
                        continue;
                    }
                    while (copy--)
                        state.lens[state.have++] = (unsigned short)len;
                }
            }

            /* handle error breaks in while */
            if (state.mode == inflate_mode.BAD) continue;

            /* check for end-of-block code (better have one) */
            if (state.lens[256] == 0) {
                strm.msg = (char *)"invalid code -- missing end-of-block";
                state.mode = inflate_mode.BAD;
                continue;
            }

            /* build code tables -- note: do not change the lenbits or distbits
               values here (9 and 6) without reading the comments in inftrees.h
               concerning the ENOUGH constants, which depend on those values */
            state.next = state.codes;
            state.lencode = (const code FAR *)(state.next);
            state.lenbits = 9;
            ret = inflate_table(LENS, state.lens, state.nlen, &(state.next),
                                &(state.lenbits), state.work);
            if (ret) {
                strm.msg = (char *)"invalid literal/lengths set";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.distcode = (const code FAR *)(state.next);
            state.distbits = 6;
            ret = inflate_table(DISTS, state.lens + state.nlen, state.ndist,
                            &(state.next), &(state.distbits), state.work);
            if (ret) {
                strm.msg = (char *)"invalid distances set";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.mode = inflate_mode.LEN_;
            if (flush == Z_TREES) goto inf_leave;
        case inflate_mode.LEN_:
            state.mode = inflate_mode.LEN;
        case inflate_mode.LEN:
            if (have >= 6 && left >= 258) {
                RESTORE();
                inflate_fast(strm, out);
                put = strm.next_out;
                left = strm.avail_out;
                next = strm.next_in;
                have = strm.avail_in;
                hold = state.hold;
                bits = state.bits;
                if (state.mode == inflate_mode.TYPE)
                    state.back = -1;
                continue;
            }
            state.back = 0;
            for (;;) {
                here = state.lencode[BITS(hold, state.lenbits)];
                if ((unsigned)(here.bits) <= bits) break;
                PULLBYTE();
            }
            if (here.op && (here.op & 0xf0) == 0) {
                last = here;
                for (;;) {
                    here = state.lencode[last.val +
                            (BITS(hold, last.bits + last.op) >> last.bits)];
                    if ((unsigned)(last.bits + here.bits) <= bits) break;
                    PULLBYTE();
                }
                hold >>= last.bits;
                bits -= last.bits;
                state.back += last.bits;
            }
            hold >>= here.bits;
            bits -= here.bits;
            state.back += here.bits;
            state.length = (unsigned)here.val;
            if ((int)(here.op) == 0) {
                Tracevv((stderr, here.val >= 0x20 && here.val < 0x7f ?
                        "inflate:         literal '%c'\n" :
                        "inflate:         literal 0x%02x\n", here.val));
                state.mode = inflate_mode.LIT;
                continue;
            }
            if (here.op & 32) {
                Tracevv((stderr, "inflate:         end of block\n"));
                state.back = -1;
                state.mode = inflate_mode.TYPE;
                continue;
            }
            if (here.op & 64) {
                strm.msg = (char *)"invalid literal/length code";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.extra = (unsigned)(here.op) & 15;
            state.mode = inflate_mode.LENEXT;
        case inflate_mode.LENEXT:
            if (state.extra) {
                NEEDBITS(state.extra);
                state.length += BITS(hold, state.extra);
                hold >>= state.extra;
                bits -= state.extra;
                state.back += state.extra;
            }
            Tracevv((stderr, "inflate:         length %u\n", state.length));
            state.was = state.length;
            state.mode = inflate_mode.DIST;
        case inflate_mode.DIST:
            for (;;) {
                here = state.distcode[BITS(hold, state.distbits)];
                if ((unsigned)(here.bits) <= bits) break;
                PULLBYTE();
            }
            if ((here.op & 0xf0) == 0) {
                last = here;
                for (;;) {
                    here = state.distcode[last.val +
                            (BITS(hold, last.bits + last.op) >> last.bits)];
                    if ((unsigned)(last.bits + here.bits) <= bits) break;
                    PULLBYTE();
                }
                hold >>= last.bits;
                bits -= last.bits;
                state.back += last.bits;
            }
            hold >>= here.bits;
            bits -= here.bits;
            state.back += here.bits;
            if (here.op & 64) {
                strm.msg = (char *)"invalid distance code";
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.offset = (unsigned)here.val;
            state.extra = (unsigned)(here.op) & 15;
            state.mode = inflate_mode.DISTEXT;
        case inflate_mode.DISTEXT:
            if (state.extra) {
                NEEDBITS(state.extra);
                state.offset += BITS(hold, state.extra);
                hold >>= state.extra;
                bits -= state.extra;
                state.back += state.extra;
            }
            Tracevv((stderr, "inflate:         distance %u\n", state.offset));
            state.mode = inflate_mode.MATCH;
        case inflate_mode.MATCH:
            if (left == 0) goto inf_leave;
            copy = out - left;
            if (state.offset > copy) {         /* copy from window */
                copy = state.offset - copy;
                if (copy > state.whave) {
                    if (state.sane) {
                        strm.msg = (char *)"invalid distance too far back";
                        state.mode = inflate_mode.BAD;
                        continue;
                    }
                }
                if (copy > state.wnext) {
                    copy -= state.wnext;
                    from = state.window + (state.wsize - copy);
                }
                else
                    from = state.window + (state.wnext - copy);
                if (copy > state.length) copy = state.length;
            }
            else {                              /* copy from output */
                from = put - state.offset;
                copy = state.length;
            }
            if (copy > left) copy = left;
            left -= copy;
            state.length -= copy;
            do {
                *put++ = *from++;
            } while (--copy);
            if (state.length == 0) state.mode = inflate_mode.LEN;
            continue;
        case inflate_mode.LIT:
            if (left == 0) goto inf_leave;
            *put++ = (unsigned char)(state.length);
            left--;
            state.mode = inflate_mode.LEN;
            continue;
        case inflate_mode.CHECK:
            if (state.wrap) {
                NEEDBITS(32);
                out -= left;
                strm.total_out += out;
                state.total += out;
                if (out)
                    strm.adler = state.check =
                        UPDATE(state.check, put - out, out);
                out = left;
                if ((state.flags ? hold : ZSWAP32(hold)) != state.check) {
                    strm.msg = (char *)"incorrect data check";
                    state.mode = inflate_mode.BAD;
                    continue;
                }
                hold = 0;
                bits = 0;
            }
            state.mode = inflate_mode.LENGTH;
        case inflate_mode.LENGTH:
            if (state.wrap && state.flags) {
                NEEDBITS(32);
                if (hold != (state.total & 0xffffffffUL)) {
                    strm.msg = (char *)"incorrect length check";
                    state.mode = inflate_mode.BAD;
                    continue;
                }
                hold = 0;
                bits = 0;
            }
            state.mode = inflate_mode.DONE;
        case inflate_mode.DONE:
            ret = Z_STREAM_END;
            goto inf_leave;
        case inflate_mode.BAD:
            ret = Z_DATA_ERROR;
            goto inf_leave;
        case inflate_mode.MEM:
            return Z_MEM_ERROR;
        case inflate_mode.SYNC:
        default:
      */
      else => return error.CorruptState,
    }
  }

    /*
       Return from inflate(), updating the total counts and the check value.
       If there was no progress during the inflate() call, return a buffer
       error.  Call updatewindow() to create and/or update the window state.
       Note: a memory error from inflate() is non-recoverable.
     */
  // TODO: goto
  // inf_leave:
  /*
    RESTORE();
    if (state.wsize || (out != strm.avail_out && state.mode < BAD &&
            (state.mode < CHECK || flush != Z_FINISH)))
        if (updatewindow(strm, strm.next_out, out - strm.avail_out)) {
            state.mode = inflate_mode.MEM;
            return Z_MEM_ERROR;
        }
    in -= strm.avail_in;
    out -= strm.avail_out;
    strm.total_in += in;
    strm.total_out += out;
    state.total += out;
    if (state.wrap && out)
        strm.adler = state.check =
            UPDATE(state.check, strm.next_out - out, out);
    strm.data_type = state.bits + (state.last ? 64 : 0) +
                      (state.mode == inflate_mode.TYPE ? 128 : 0) +
                      (state.mode == inflate_mode.LEN_ || state.mode == inflate_mode.COPY_ ? 256 : 0);
    if (((in == 0 && out == 0) || flush == Z_FINISH) && ret == Z_OK)
        ret = Z_BUF_ERROR;
    return ret;
  */
}

#attribute("test")
fn test_inflate() {
  %%io.stdout.printf("\n");

  var strm: z_stream = undefined;
  inflateInit(&strm);

  %%io.stdout.print_u64(@sizeof(z_stream));
  %%io.stdout.printf("\n");

  %%io.stdout.flush();
}
