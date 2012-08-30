#ifndef TARANTOOL_SALLOC_H_INCLUDED
#define TARANTOOL_SALLOC_H_INCLUDED
/*
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *    copyright notice, this list of conditions and the
 *    following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
#include <stddef.h>
#include <stdbool.h>
#include "util.h" /* for u64 */

struct tbuf;

bool salloc_init(size_t size, size_t minimal, double factor);
void salloc_destroy(void);
void *salloc(size_t size, const char *what);
void sfree(void *ptr);
void slab_validate();


struct one_slab_stat {
	i64 item_size;
	i64 slabs;
	i64 items;
	i64 bytes_used;
	i64 bytes_free;
};

struct arena_stat {
	size_t size;
	size_t used;
};

void full_slab_stat(
	int (*cb)(const struct one_slab_stat *st, void *udata),
	struct arena_stat *stat,
	void *data
);

// void
// slab_stat2(u64 *bytes_used, u64 *items);
#endif /* TARANTOOL_SALLOC_H_INCLUDED */
