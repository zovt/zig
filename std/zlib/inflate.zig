const io = @import("std").io;
const str_eql = @import("std").str_eql;

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
    whave: isize,           /* valid bytes in the window */
    wnext: isize,           /* window write index */
    window: [WINDOW_SIZE]u8,/* sliding window, if needed */
        /* bit accumulator */
    hold: u32,              /* input bit accumulator */
    bits: u32,              /* number of bits in "in" */
        /* for string and stored block copying */
    length: isize,          /* literal or length of data to copy */
    offset: isize,          /* distance back to copy string from */
        /* for table and code decoding */
    extra: u8,              /* extra bits needed (value always in range [0,15]) */
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
    was: isize,             /* initial length of match */
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
    input_buf: []u8,
    total_in: u32,       /* total number of input bytes read so far */

    output_buf: []u8,
    total_out: u32,      /* total number of bytes output so far */

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

error CorruptState;
error IncorrectHeaderCheck;
error UnknownCompressionMethod;
error InvalidWindowSize;
error InvalidBlockType;
error InvalidStoredBlockLengths;
error UnknownHeaderFlagsSet;
error HeaderCrcMismatch;
error TooManyLengthOrDistanceSymbols;
error InvalidCodeLengthsSet;
error InvalidBitLengthRepeat;
error InvalidCode_MissingEndOfBlock;
error InvalidLiteralLengthsSet;
error InvalidDistancesSet;
error InvalidLiteralLengthCode;
error InvalidDistanceCode;
error InvalidDistanceTooFarBack;
error IncorrectDataCheck;
error IncorrectLengthCheck;

/* permutation of code lengths */
const order = []u16{
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
};

enum FlushMode {
  Z_NO_FLUSH,
  Z_PARTIAL_FLUSH,
  Z_SYNC_FLUSH,
  Z_FULL_FLUSH,
  Z_FINISH,
  Z_BLOCK,
  Z_TREES,
}

fn BITS(hold: u32, n: u32) -> u32 {
    return hold & ((1 << n) - 1);
}
pub fn inflate(strm: &z_stream, flush: FlushMode) -> %void {
  var state = &strm.state;

  var next: []u8 = undefined;      /* next input */
  var put: []u8 = undefined;       /* next output */
  // var have: u32 = undefined; now: next.len      /* available input and output */
  // var left: u32 = undefined; now: put.len       /* available input and output */
  var hold: u32 = undefined;       /* bit buffer */
  var bits: u32 = undefined;       /* bits in bit buffer */
  var in: isize = undefined;       /* save starting available input and output */
  var out: isize = undefined;      /* save starting available input and output */
  var copy: isize = undefined;     /* number of stored or match bytes to copy */
  var from: &u8 = undefined;       /* where to copy match bytes from */
  var here: code = undefined;      /* current decoding table entry */
  var last: code = undefined;      /* parent table entry */
  var len: u32 = undefined;        /* length to copy for repeats, bits to drop */
  var ret: %void = void{};         /* return code */
  var hbuf: [4]u8 = undefined;     /* buffer for gzip header crc calculation */

  put = strm.output_buf;
  next = strm.input_buf;
  hold = state.hold;
  bits = state.bits;

  if (state.mode == inflate_mode.TYPE) state.mode = inflate_mode.TYPEDO;      /* skip check */

  in = next.len;
  out = put.len;
  @breakpoint();
  while (true) {
    switch (state.mode) {
      HEAD => {
        if (state.wrap == 0) {
          state.mode = inflate_mode.TYPEDO;
          continue;
        }
        while (bits < 16) {
          if (next.len == 0) goto inf_leave;
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
          ret = error.IncorrectHeaderCheck;
          state.mode = inflate_mode.BAD;
          continue;
        }
        if (BITS(hold, 4) != Z_DEFLATED) {
          ret = error.UnknownCompressionMethod;
          state.mode = inflate_mode.BAD;
          continue;
        }
        hold >>= 4;
        bits -= 4;
        len = BITS(hold, 4) + 8;
        if (state.wbits == 0) {
          state.wbits = len;
        } else if (len > state.wbits) {
          ret = error.InvalidWindowSize;
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
            while (bits < 16) {
              if (next.len == 0) goto inf_leave;
              hold += u32(next[0]) << bits;
              next = next[1...];
              bits += 8;
            }
            state.flags = (int)(hold);
            if ((state.flags & 0xff) != Z_DEFLATED) {
                ret = error.UnknownCompressionMethod;
                state.mode = inflate_mode.BAD;
                continue;
            }
            if (state.flags & 0xe000) {
                ret = error.UnknownHeaderFlagsSet;
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
            while (bits < 32) {
              if (next.len == 0) goto inf_leave;
              hold += u32(next[0]) << bits;
              next = next[1...];
              bits += 8;
            }
            if (state.head != Z_NULL)
                state.head.time = hold;
            if (state.flags & 0x0200) CRC4(state.check, hold);
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.OS;
        case inflate_mode.OS:
            while (bits < 16) {
              if (next.len == 0) goto inf_leave;
              hold += u32(next[0]) << bits;
              next = next[1...];
              bits += 8;
            }
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
                while (bits < 16) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
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
                if (copy > next.len) copy = next.len;
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
                    next.len -= copy;
                    next += copy;
                    state.length -= copy;
                }
                if (state.length) goto inf_leave;
            }
            state.length = 0;
            state.mode = inflate_mode.NAME;
        case inflate_mode.NAME:
            if (state.flags & 0x0800) {
                if (next.len == 0) goto inf_leave;
                copy = 0;
                do {
                    len = (unsigned)(next[copy++]);
                    if (state.head != Z_NULL &&
                            state.head.name != Z_NULL &&
                            state.length < state.head.name_max)
                        state.head.name[state.length++] = len;
                } while (len && copy < next.len);
                if (state.flags & 0x0200)
                    state.check = crc32(state.check, next, copy);
                next.len -= copy;
                next += copy;
                if (len) goto inf_leave;
            }
            else if (state.head != Z_NULL)
                state.head.name = Z_NULL;
            state.length = 0;
            state.mode = inflate_mode.COMMENT;
        case inflate_mode.COMMENT:
            if (state.flags & 0x1000) {
                if (next.len == 0) goto inf_leave;
                copy = 0;
                do {
                    len = (unsigned)(next[copy++]);
                    if (state.head != Z_NULL &&
                            state.head.comment != Z_NULL &&
                            state.length < state.head.comm_max)
                        state.head.comment[state.length++] = len;
                } while (len && copy < next.len);
                if (state.flags & 0x0200)
                    state.check = crc32(state.check, next, copy);
                next.len -= copy;
                next += copy;
                if (len) goto inf_leave;
            }
            else if (state.head != Z_NULL)
                state.head.comment = Z_NULL;
            state.mode = inflate_mode.HCRC;
        case inflate_mode.HCRC:
            if (state.flags & 0x0200) {
                while (bits < 16) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
                if (hold != (state.check & 0xffff)) {
                    ret = error.HeaderCrcMismatch;
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
            while (bits < 32) {
              if (next.len == 0) goto inf_leave;
              hold += u32(next[0]) << bits;
              next = next[1...];
              bits += 8;
            }
            strm.adler = state.check = ZSWAP32(hold);
            hold = 0;
            bits = 0;
            state.mode = inflate_mode.DICT;
        case inflate_mode.DICT:
            if (state.havedict == 0) {
                strm.output_buf = put;
                strm.input_buf = next;
                state.hold = hold;
                state.bits = bits;
                return Z_NEED_DICT;
            }
            strm.adler = state.check = adler32(0L, Z_NULL, 0);
            state.mode = inflate_mode.TYPE;
      */
      TYPE => {
        if (flush == FlushMode.Z_BLOCK || flush == FlushMode.Z_TREES) goto inf_leave;
        state.mode = inflate_mode.TYPEDO;
      },
      TYPEDO => {
        if (state.last) {
          /* go to byte boundary */
          hold >>= bits & 7;
          bits -= bits & 7;
          state.mode = inflate_mode.CHECK;
          continue;
        }
        while (bits < 3) {
          if (next.len == 0) goto inf_leave;
          hold += u32(next[0]) << bits;
          next = next[1...];
          bits += 8;
        }
        state.last = BITS(hold, 1) != 0;
        hold >>= 1;
        bits -= 1;
        switch (BITS(hold, 2)) {
          0 => { /* stored block */
            state.mode = inflate_mode.STORED;
          },
          1 => { /* fixed block */
            fixedtables(state);
            state.mode = inflate_mode.LEN_;             /* decode codes */
            if (flush == FlushMode.Z_TREES) {
              hold >>= 2;
              bits -= 2;
              goto inf_leave;
            }
          },
          2 => { /* dynamic block */
            state.mode = inflate_mode.TABLE;
          },
          3 => {
            ret = error.InvalidBlockType;
            state.mode = inflate_mode.BAD;
          },
          else => unreachable{},
        }
        hold >>= 2;
        bits -= 2;
        continue;
      },
      STORED => {
        /* go to byte boundary */
        hold >>= bits & 7;
        bits -= bits & 7;
        while (bits < 32) {
          if (next.len == 0) goto inf_leave;
          hold += u32(next[0]) << bits;
          next = next[1...];
          bits += 8;
        }
        // TODO: use ~
        if (hold & 0xffff != (hold >> 16) ^ 0xffff) {
          ret = error.InvalidStoredBlockLengths;
          state.mode = inflate_mode.BAD;
          continue;
        }
        state.length = isize(hold & 0xffff);
        hold = 0;
        bits = 0;
        state.mode = inflate_mode.COPY_;
        if (flush == FlushMode.Z_TREES) goto inf_leave;
      },
      COPY_ => {
        state.mode = inflate_mode.COPY;
      },
      COPY => {
        copy = state.length;
        if (copy != 0) {
          if (copy > next.len) copy = next.len;
          if (copy > put.len) copy = put.len;
          if (copy == 0) goto inf_leave;
          @memcpy(&put[0], &next[0], copy);
          next = next[copy...];
          put = put[copy...];
          state.length -= copy;
          continue;
        }
        state.mode = inflate_mode.TYPE;
        continue;
      },
      /*
        case inflate_mode.TABLE:
            while (bits < 14) {
              if (next.len == 0) goto inf_leave;
              hold += u32(next[0]) << bits;
              next = next[1...];
              bits += 8;
            }
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
                ret = error.TooManyLengthOrDistanceSymbols;
                state.mode = BAD;
                break;
            }
            state.have = 0;
            state.mode = inflate_mode.LENLENS;
        case inflate_mode.LENLENS:
            while (state.have < state.ncode) {
                while (bits < 3) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
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
                ret = error.InvalidCodeLengthsSet;
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.have = 0;
            state.mode = inflate_mode.CODELENS;
        case inflate_mode.CODELENS:
            while (state.have < state.nlen + state.ndist) {
                while (true) {
                    here = state.lencode[BITS(hold, state.lenbits)];
                    if ((unsigned)(here.bits) <= bits) break;
                    if (next.len == 0) goto inf_leave;
                    hold += u32(next[0]) << bits;
                    next = next[1...];
                    bits += 8;
                }
                if (here.val < 16) {
                    hold >>= here.bits;
                    bits -= here.bits;
                    state.lens[state.have++] = here.val;
                }
                else {
                    if (here.val == 16) {
                        while (bits < here.bits + 2) {
                          if (next.len == 0) goto inf_leave;
                          hold += u32(next[0]) << bits;
                          next = next[1...];
                          bits += 8;
                        }
                        hold >>= here.bits;
                        bits -= here.bits;
                        if (state.have == 0) {
                            ret = error.InvalidBitLengthRepeat;
                            state.mode = inflate_mode.BAD;
                            continue;
                        }
                        len = state.lens[state.have - 1];
                        copy = 3 + BITS(hold, 2);
                        hold >>= 2;
                        bits -= 2;
                    }
                    else if (here.val == 17) {
                        while (bits < here.bits + 3) {
                          if (next.len == 0) goto inf_leave;
                          hold += u32(next[0]) << bits;
                          next = next[1...];
                          bits += 8;
                        }
                        hold >>= here.bits;
                        bits -= here.bits;
                        len = 0;
                        copy = 3 + BITS(hold, 3);
                        hold >>= 3;
                        bits -= 3;
                    }
                    else {
                        while (bits < here.bits + 7) {
                          if (next.len == 0) goto inf_leave;
                          hold += u32(next[0]) << bits;
                          next = next[1...];
                          bits += 8;
                        }
                        hold >>= here.bits;
                        bits -= here.bits;
                        len = 0;
                        copy = 11 + BITS(hold, 7);
                        hold >>= 7;
                        bits -= 7;
                    }
                    if (state.have + copy > state.nlen + state.ndist) {
                        ret = error.InvalidBitLengthRepeat;
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
                ret = error.InvalidCode_MissingEndOfBlock;
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
                ret = error.InvalidLiteralLengthsSet;
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.distcode = (const code FAR *)(state.next);
            state.distbits = 6;
            ret = inflate_table(DISTS, state.lens + state.nlen, state.ndist,
                            &(state.next), &(state.distbits), state.work);
            if (ret) {
                ret = error.InvalidDistancesSet;
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.mode = inflate_mode.LEN_;
            if (flush == FlushMode.Z_TREES) goto inf_leave;
        */
        LEN_ => {
          state.mode = inflate_mode.LEN;
        },
        LEN => {
            if (next.len >= 6 && put.len >= 258) {
                strm.output_buf = put;
                strm.input_buf = next;
                state.hold = hold;
                state.bits = bits;

                inflate_fast(strm, out);

                put = strm.output_buf;
                next = strm.input_buf;
                hold = state.hold;
                bits = state.bits;

                if (state.mode == inflate_mode.TYPE)
                    state.back = -1;
                continue;
            }
            state.back = 0;
            while (true) {
                // TODO: shouldn't have to cast to isize
                here = state.lencode[isize(BITS(hold, state.lenbits))];
                if (here.bits <= bits) break;
                if (next.len == 0) goto inf_leave;
                hold += u32(next[0]) << bits;
                next = next[1...];
                bits += 8;
            }
            if (here.op != 0 && (here.op & 0xf0) == 0) {
                last = here;
                while (true) {
                    // TODO: shouldn't have to cast to isize
                    here = state.lencode[isize(last.val +
                            (BITS(hold, last.bits + last.op) >> last.bits))];
                    if (last.bits + here.bits <= bits) break;
                    if (next.len == 0) goto inf_leave;
                    hold += u32(next[0]) << bits;
                    next = next[1...];
                    bits += 8;
                }
                hold >>= last.bits;
                bits -= last.bits;
                state.back += last.bits;
            }
            hold >>= here.bits;
            bits -= here.bits;
            state.back += here.bits;
            state.length = here.val;
            if (here.op == 0) {
                state.mode = inflate_mode.LIT;
                continue;
            }
            if (here.op & 32 != 0) {
                state.back = -1;
                state.mode = inflate_mode.TYPE;
                continue;
            }
            if (here.op & 64 != 0) {
                ret = error.InvalidLiteralLengthCode;
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.extra = here.op & 15;
            state.mode = inflate_mode.LENEXT;
        },
        LENEXT => {
            if (state.extra != 0) {
                while (bits < state.extra) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
                state.length += u16(BITS(hold, state.extra));
                hold >>= state.extra;
                bits -= state.extra;
                state.back += i32(state.extra);
            }
            state.was = state.length;
            state.mode = inflate_mode.DIST;
        },
        DIST => {
            while (true) {
                // TODO: shouldn't have to cast to isize
                here = state.distcode[isize(BITS(hold, state.distbits))];
                if (here.bits <= bits) break;
                if (next.len == 0) goto inf_leave;
                hold += u32(next[0]) << bits;
                next = next[1...];
                bits += 8;
            }
            if ((here.op & 0xf0) == 0) {
                last = here;
                while (true) {
                    // TODO: shouldn't have to cast to isize
                    here = state.distcode[isize(last.val +
                            (BITS(hold, last.bits + last.op) >> last.bits))];
                    if (last.bits + here.bits <= bits) break;
                    if (next.len == 0) goto inf_leave;
                    hold += u32(next[0]) << bits;
                    next = next[1...];
                    bits += 8;
                }
                hold >>= last.bits;
                bits -= last.bits;
                state.back += last.bits;
            }
            hold >>= here.bits;
            bits -= here.bits;
            state.back += here.bits;
            if ((here.op & 64) != 0) {
                ret = error.InvalidDistanceCode;
                state.mode = inflate_mode.BAD;
                continue;
            }
            state.offset = here.val;
            state.extra = here.op & 15;
            state.mode = inflate_mode.DISTEXT;
        },
        DISTEXT => {
            if (state.extra != 0) {
                while (bits < state.extra) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
                state.offset += u16(BITS(hold, state.extra));
                hold >>= state.extra;
                bits -= state.extra;
                state.back += state.extra;
            }
            state.mode = inflate_mode.MATCH;
        },
        MATCH => {
            if (put.len == 0) goto inf_leave;
            copy = out - put.len;
            if (state.offset > copy) {         /* copy from window */
                copy = state.offset - copy;
                if (copy > state.whave) {
                    if (state.sane) {
                        ret = error.InvalidDistanceTooFarBack;
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
            if (copy > put.len) copy = put.len;
            put.len -= copy;
            state.length -= copy;
            @memcpy(&put[0], &from[0], copy);
            if (state.length == 0) state.mode = inflate_mode.LEN;
            continue;
        },
        /*
        case inflate_mode.LIT:
            if (put.len == 0) goto inf_leave;
            *put++ = (unsigned char)(state.length);
            put.len--;
            state.mode = inflate_mode.LEN;
            continue;
        case inflate_mode.CHECK:
            if (state.wrap) {
                while (bits < 32) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
                out -= put.len;
                strm.total_out += out;
                state.total += out;
                if (out)
                    strm.adler = state.check =
                        UPDATE(state.check, put - out, out);
                out = put.len;
                if ((state.flags ? hold : ZSWAP32(hold)) != state.check) {
                    ret = error.IncorrectDataCheck;
                    state.mode = inflate_mode.BAD;
                    continue;
                }
                hold = 0;
                bits = 0;
            }
            state.mode = inflate_mode.LENGTH;
        case inflate_mode.LENGTH:
            if (state.wrap && state.flags) {
                while (bits < 32) {
                  if (next.len == 0) goto inf_leave;
                  hold += u32(next[0]) << bits;
                  next = next[1...];
                  bits += 8;
                }
                if (hold != (state.total & 0xffffffffUL)) {
                    ret = error.IncorrectLengthCheck;
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
      */
        BAD => {
          goto inf_leave;
        },
      /*
        case inflate_mode.MEM:
            return Z_MEM_ERROR;
        case inflate_mode.SYNC:
        default:
      */
      else => {
        //@breakpoint();
        return error.CorruptState;
      },
    }
  }

  /*
     Return from inflate(), updating the total counts and the check value.
     If there was no progress during the inflate() call, return a buffer
     error.  Call updatewindow() to create and/or update the window state.
     Note: a memory error from inflate() is non-recoverable.
   */
  inf_leave:

  RESTORE();
  if (state.wsize || (out != strm.avail_out && state.mode < BAD &&
          (state.mode < CHECK || flush != FlushMode.Z_FINISH)))
      if (updatewindow(strm, strm.next_out, out - strm.avail_out)) {
          state.mode = inflate_mode.MEM;
          return Z_MEM_ERROR;
      }
  in -= strm.avail_in;
  out -= strm.avail_out;
  strm.total_in += in;
  strm.total_out += out;
  state.total += out;
  if (state.wrap && out) {
      state.check = UPDATE(state.check, strm.next_out - out, out);
      strm.adler = state.check;
  }
  // TODO: https://github.com/andrewrk/zig/issues/136
  // strm.data_type = state.bits +
  //   (if (state.last) 64 else 0) +
  //   (if (state.mode == inflate_mode.TYPE) 128 else 0) +
  //   (if (state.mode == inflate_mode.LEN_ || state.mode == inflate_mode.COPY_) 256 else 0);
  if (((in == 0 && out == 0) || flush == FlushMode.Z_FINISH) && ret == Z_OK)
      ret = Z_BUF_ERROR;
  return ret;
}

fn inflate_fast(strm: &z_stream, start: isize)
{
  // TODO
  unreachable{};
}


fn c(op: u8, bits: u8, val: u16) -> code {
  return code{.op=op, .bits=bits, .val=val};
}
const lenfix = []code{
  /*
  c(96,7,0),c(0,8,80),c(0,8,16),c(20,8,115),c(18,7,31),c(0,8,112),c(0,8,48),
  c(0,9,192),c(16,7,10),c(0,8,96),c(0,8,32),c(0,9,160),c(0,8,0),c(0,8,128),
  c(0,8,64),c(0,9,224),c(16,7,6),c(0,8,88),c(0,8,24),c(0,9,144),c(19,7,59),
  c(0,8,120),c(0,8,56),c(0,9,208),c(17,7,17),c(0,8,104),c(0,8,40),c(0,9,176),
  c(0,8,8),c(0,8,136),c(0,8,72),c(0,9,240),c(16,7,4),c(0,8,84),c(0,8,20),
  c(21,8,227),c(19,7,43),c(0,8,116),c(0,8,52),c(0,9,200),c(17,7,13),c(0,8,100),
  c(0,8,36),c(0,9,168),c(0,8,4),c(0,8,132),c(0,8,68),c(0,9,232),c(16,7,8),
  c(0,8,92),c(0,8,28),c(0,9,152),c(20,7,83),c(0,8,124),c(0,8,60),c(0,9,216),
  c(18,7,23),c(0,8,108),c(0,8,44),c(0,9,184),c(0,8,12),c(0,8,140),c(0,8,76),
  c(0,9,248),c(16,7,3),c(0,8,82),c(0,8,18),c(21,8,163),c(19,7,35),c(0,8,114),
  c(0,8,50),c(0,9,196),c(17,7,11),c(0,8,98),c(0,8,34),c(0,9,164),c(0,8,2),
  c(0,8,130),c(0,8,66),c(0,9,228),c(16,7,7),c(0,8,90),c(0,8,26),c(0,9,148),
  c(20,7,67),c(0,8,122),c(0,8,58),c(0,9,212),c(18,7,19),c(0,8,106),c(0,8,42),
  c(0,9,180),c(0,8,10),c(0,8,138),c(0,8,74),c(0,9,244),c(16,7,5),c(0,8,86),
  c(0,8,22),c(64,8,0),c(19,7,51),c(0,8,118),c(0,8,54),c(0,9,204),c(17,7,15),
  c(0,8,102),c(0,8,38),c(0,9,172),c(0,8,6),c(0,8,134),c(0,8,70),c(0,9,236),
  c(16,7,9),c(0,8,94),c(0,8,30),c(0,9,156),c(20,7,99),c(0,8,126),c(0,8,62),
  c(0,9,220),c(18,7,27),c(0,8,110),c(0,8,46),c(0,9,188),c(0,8,14),c(0,8,142),
  c(0,8,78),c(0,9,252),c(96,7,0),c(0,8,81),c(0,8,17),c(21,8,131),c(18,7,31),
  c(0,8,113),c(0,8,49),c(0,9,194),c(16,7,10),c(0,8,97),c(0,8,33),c(0,9,162),
  c(0,8,1),c(0,8,129),c(0,8,65),c(0,9,226),c(16,7,6),c(0,8,89),c(0,8,25),
  c(0,9,146),c(19,7,59),c(0,8,121),c(0,8,57),c(0,9,210),c(17,7,17),c(0,8,105),
  c(0,8,41),c(0,9,178),c(0,8,9),c(0,8,137),c(0,8,73),c(0,9,242),c(16,7,4),
  c(0,8,85),c(0,8,21),c(16,8,258),c(19,7,43),c(0,8,117),c(0,8,53),c(0,9,202),
  c(17,7,13),c(0,8,101),c(0,8,37),c(0,9,170),c(0,8,5),c(0,8,133),c(0,8,69),
  c(0,9,234),c(16,7,8),c(0,8,93),c(0,8,29),c(0,9,154),c(20,7,83),c(0,8,125),
  c(0,8,61),c(0,9,218),c(18,7,23),c(0,8,109),c(0,8,45),c(0,9,186),c(0,8,13),
  c(0,8,141),c(0,8,77),c(0,9,250),c(16,7,3),c(0,8,83),c(0,8,19),c(21,8,195),
  c(19,7,35),c(0,8,115),c(0,8,51),c(0,9,198),c(17,7,11),c(0,8,99),c(0,8,35),
  c(0,9,166),c(0,8,3),c(0,8,131),c(0,8,67),c(0,9,230),c(16,7,7),c(0,8,91),
  c(0,8,27),c(0,9,150),c(20,7,67),c(0,8,123),c(0,8,59),c(0,9,214),c(18,7,19),
  c(0,8,107),c(0,8,43),c(0,9,182),c(0,8,11),c(0,8,139),c(0,8,75),c(0,9,246),
  c(16,7,5),c(0,8,87),c(0,8,23),c(64,8,0),c(19,7,51),c(0,8,119),c(0,8,55),
  c(0,9,206),c(17,7,15),c(0,8,103),c(0,8,39),c(0,9,174),c(0,8,7),c(0,8,135),
  c(0,8,71),c(0,9,238),c(16,7,9),c(0,8,95),c(0,8,31),c(0,9,158),c(20,7,99),
  c(0,8,127),c(0,8,63),c(0,9,222),c(18,7,27),c(0,8,111),c(0,8,47),c(0,9,190),
  c(0,8,15),c(0,8,143),c(0,8,79),c(0,9,254),c(96,7,0),c(0,8,80),c(0,8,16),
  c(20,8,115),c(18,7,31),c(0,8,112),c(0,8,48),c(0,9,193),c(16,7,10),c(0,8,96),
  c(0,8,32),c(0,9,161),c(0,8,0),c(0,8,128),c(0,8,64),c(0,9,225),c(16,7,6),
  c(0,8,88),c(0,8,24),c(0,9,145),c(19,7,59),c(0,8,120),c(0,8,56),c(0,9,209),
  c(17,7,17),c(0,8,104),c(0,8,40),c(0,9,177),c(0,8,8),c(0,8,136),c(0,8,72),
  c(0,9,241),c(16,7,4),c(0,8,84),c(0,8,20),c(21,8,227),c(19,7,43),c(0,8,116),
  c(0,8,52),c(0,9,201),c(17,7,13),c(0,8,100),c(0,8,36),c(0,9,169),c(0,8,4),
  c(0,8,132),c(0,8,68),c(0,9,233),c(16,7,8),c(0,8,92),c(0,8,28),c(0,9,153),
  c(20,7,83),c(0,8,124),c(0,8,60),c(0,9,217),c(18,7,23),c(0,8,108),c(0,8,44),
  c(0,9,185),c(0,8,12),c(0,8,140),c(0,8,76),c(0,9,249),c(16,7,3),c(0,8,82),
  c(0,8,18),c(21,8,163),c(19,7,35),c(0,8,114),c(0,8,50),c(0,9,197),c(17,7,11),
  c(0,8,98),c(0,8,34),c(0,9,165),c(0,8,2),c(0,8,130),c(0,8,66),c(0,9,229),
  c(16,7,7),c(0,8,90),c(0,8,26),c(0,9,149),c(20,7,67),c(0,8,122),c(0,8,58),
  c(0,9,213),c(18,7,19),c(0,8,106),c(0,8,42),c(0,9,181),c(0,8,10),c(0,8,138),
  c(0,8,74),c(0,9,245),c(16,7,5),c(0,8,86),c(0,8,22),c(64,8,0),c(19,7,51),
  c(0,8,118),c(0,8,54),c(0,9,205),c(17,7,15),c(0,8,102),c(0,8,38),c(0,9,173),
  c(0,8,6),c(0,8,134),c(0,8,70),c(0,9,237),c(16,7,9),c(0,8,94),c(0,8,30),
  c(0,9,157),c(20,7,99),c(0,8,126),c(0,8,62),c(0,9,221),c(18,7,27),c(0,8,110),
  c(0,8,46),c(0,9,189),c(0,8,14),c(0,8,142),c(0,8,78),c(0,9,253),c(96,7,0),
  c(0,8,81),c(0,8,17),c(21,8,131),c(18,7,31),c(0,8,113),c(0,8,49),c(0,9,195),
  c(16,7,10),c(0,8,97),c(0,8,33),c(0,9,163),c(0,8,1),c(0,8,129),c(0,8,65),
  c(0,9,227),c(16,7,6),c(0,8,89),c(0,8,25),c(0,9,147),c(19,7,59),c(0,8,121),
  c(0,8,57),c(0,9,211),c(17,7,17),c(0,8,105),c(0,8,41),c(0,9,179),c(0,8,9),
  c(0,8,137),c(0,8,73),c(0,9,243),c(16,7,4),c(0,8,85),c(0,8,21),c(16,8,258),
  c(19,7,43),c(0,8,117),c(0,8,53),c(0,9,203),c(17,7,13),c(0,8,101),c(0,8,37),
  c(0,9,171),c(0,8,5),c(0,8,133),c(0,8,69),c(0,9,235),c(16,7,8),c(0,8,93),
  c(0,8,29),c(0,9,155),c(20,7,83),c(0,8,125),c(0,8,61),c(0,9,219),c(18,7,23),
  c(0,8,109),c(0,8,45),c(0,9,187),c(0,8,13),c(0,8,141),c(0,8,77),c(0,9,251),
  c(16,7,3),c(0,8,83),c(0,8,19),c(21,8,195),c(19,7,35),c(0,8,115),c(0,8,51),
  c(0,9,199),c(17,7,11),c(0,8,99),c(0,8,35),c(0,9,167),c(0,8,3),c(0,8,131),
  c(0,8,67),c(0,9,231),c(16,7,7),c(0,8,91),c(0,8,27),c(0,9,151),c(20,7,67),
  c(0,8,123),c(0,8,59),c(0,9,215),c(18,7,19),c(0,8,107),c(0,8,43),c(0,9,183),
  c(0,8,11),c(0,8,139),c(0,8,75),c(0,9,247),c(16,7,5),c(0,8,87),c(0,8,23),
  c(64,8,0),c(19,7,51),c(0,8,119),c(0,8,55),c(0,9,207),c(17,7,15),c(0,8,103),
  c(0,8,39),c(0,9,175),c(0,8,7),c(0,8,135),c(0,8,71),c(0,9,239),c(16,7,9),
  c(0,8,95),c(0,8,31),c(0,9,159),c(20,7,99),c(0,8,127),c(0,8,63),c(0,9,223),
  c(18,7,27),c(0,8,111),c(0,8,47),c(0,9,191),c(0,8,15),c(0,8,143),c(0,8,79),
  c(0,9,255)
  */
  undefined
};

const distfix = []code{
  /*
  c(16,5,1),c(23,5,257),c(19,5,17),c(27,5,4097),c(17,5,5),c(25,5,1025),
  c(21,5,65),c(29,5,16385),c(16,5,3),c(24,5,513),c(20,5,33),c(28,5,8193),
  c(18,5,9),c(26,5,2049),c(22,5,129),c(64,5,0),c(16,5,2),c(23,5,385),
  c(19,5,25),c(27,5,6145),c(17,5,7),c(25,5,1537),c(21,5,97),c(29,5,24577),
  c(16,5,4),c(24,5,769),c(20,5,49),c(28,5,12289),c(18,5,13),c(26,5,3073),
  c(22,5,193),c(64,5,0)
  */
  undefined
};

fn fixedtables(state: &InflateState) {
  state.lencode = &lenfix[0];
  state.lenbits = 9;
  state.distcode = &distfix[0];
  state.distbits = 5;
}

#attribute("test")
fn test_inflate() {
  %%io.stdout.printf("\n");

  var strm: z_stream = undefined;
  inflateInit(&strm);

  var output_buf: [0x1000]u8 = undefined;
  const hello_str = "hello";
  const hello_compressed = []u8 {
    // hello:
    // 0x78, 0x9c, 0xcb, 0x48,
    // 0xcd, 0xc9, 0xc9, 0x07,
    // 0x00, 0x06, 0x2c, 0x02,
    // 0x15,

    // empty string:
    // 0x78, 0x9c, 0x03, 0x00,
    // 0x00, 0x00, 0x00, 0x01,

    // raw empty string:
    0x03, 0x00,
  };
  strm.input_buf = hello_compressed;
  strm.output_buf = output_buf;

  inflate(&strm, FlushMode.Z_FINISH) %% |err| {
    %%io.stdout.printf("got error: ");
    %%io.stdout.printf(@err_name(err));
    %%io.stdout.printf("\n");
  };

  // TODO: shouldn't have to cast to isize
  if (str_eql(hello_str, output_buf[0...isize(strm.total_out)])) {
    %%io.stdout.printf("correct output\n");
  } else {
    %%io.stdout.printf("wrong output\n");
  }

  %%io.stdout.print_u64(@sizeof(z_stream));
  %%io.stdout.printf("\n");

  %%io.stdout.flush();
}
