const io = @import("std").io;

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
    wrap: bool,             /* bit 0 true for zlib, bit 1 true for gzip */
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
    next_in: &const u8,  /* next input byte */
    avail_in: u32,       /* number of bytes available at next_in */
    total_in: u32,       /* total number of input bytes read so far */

    next_out: &u8,       /* next output byte should be put there */
    avail_out: u32,      /* remaining free space at next_out */
    total_out: u32,      /* total number of bytes output so far */

    msg: []u8,           /* last error message, NULL if no error */

    data_type: u32,      /* best guess about the data type: binary or text */
    adler: u32,          /* adler32 value of the uncompressed data */

    state: InflateState, /* "not visible by applications" */
}

const MAX_WBITS = 15;
const WINDOW_SIZE = 1 << 15;
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
  if (state.wrap) {
    /* to support ill-conceived Java test suite? */
    strm.adler = 1;
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

#attribute("test")
fn test_inflate() {
  %%io.stdout.printf("\n");

  var strm: z_stream = undefined;
  inflateInit(&strm);

  %%io.stdout.print_u64(@sizeof(z_stream));
  %%io.stdout.printf("\n");

  %%io.stdout.flush();
}
