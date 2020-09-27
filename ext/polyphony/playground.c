#ifdef POLYPHONY_PLAYGROUND

#include <netdb.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "polyphony.h"
#include "../liburing/liburing.h"
#include "ruby/thread.h"

#include <poll.h>
#include <sys/types.h>
#include <sys/eventfd.h>
#include <sys/wait.h>
#include <time.h>
#include <stdnoreturn.h>

// copied from queue.c
static inline bool cq_ring_needs_flush(struct io_uring *ring) {
	return IO_URING_READ_ONCE(*ring->sq.kflags) & IORING_SQ_CQ_OVERFLOW;
}

extern int __sys_io_uring_enter(int fd, unsigned to_submit, unsigned min_complete, unsigned flags, sigset_t *sig);

void handle_cqe(struct io_uring_cqe *cqe) {
  void *data = io_uring_cqe_get_data(cqe);
  printf("cqe data: %p\n", data);
  printf("cqe res: %d\n", cqe->res);
  printf("cqe flags: %d\n", cqe->flags);
}

void handle_ready_cqes(struct io_uring *ring) {
	bool overflow_checked = false;
  struct io_uring_cqe *cqe;
	unsigned head;
  unsigned cqe_count;

  printf("handle_ready_cqes\n");

again:
  cqe_count = 0;
  io_uring_for_each_cqe(ring, head, cqe) {
    printf("---------------------\n");
    ++cqe_count;
    handle_cqe(cqe);
  }
  printf("cqe_count: %d\n", cqe_count);
  io_uring_cq_advance(ring, cqe_count);

	if (overflow_checked) goto done;

	if (cq_ring_needs_flush(ring)) {
		__sys_io_uring_enter(ring->ring_fd, 0, 0, IORING_ENTER_GETEVENTS, NULL);
		overflow_checked = true;
		goto again;
	}

done:
	return;
}

noreturn void playground() {
  struct io_uring ring;

  io_uring_queue_init(10, &ring, 0);
  
  struct __kernel_timespec ts;
  ts.tv_sec = 3;
	ts.tv_nsec = 0;
  struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
  io_uring_prep_timeout(sqe, &ts, 0, 0);
  io_uring_sqe_set_data(sqe, (void *)13);
  printf("submit sleep op\n");
  io_uring_submit(&ring);

  struct timespec ts2;
  ts2.tv_sec = 0;
	ts2.tv_nsec = 200 * 1000000;
  printf("sleep 200msec\n");
  nanosleep(&ts2, NULL);

  //cancel
  printf("submit cancel\n");
  sqe = io_uring_get_sqe(&ring);
  io_uring_prep_cancel(sqe, (void *)13, 0);
  io_uring_sqe_set_data(sqe, (void *)14);
  io_uring_submit(&ring);

  //nop
  printf("submit nop\n");
  sqe = io_uring_get_sqe(&ring);
  io_uring_prep_nop(sqe);
  io_uring_sqe_set_data(sqe, (void *)15);
  io_uring_submit(&ring);

  ts2.tv_sec = 0;
	ts2.tv_nsec = 100 * 1000000;
  printf("sleep 100msec\n");
  nanosleep(&ts2, NULL);

  printf("wait for timer\n");
  struct io_uring_cqe *cqe;
  int ret = __io_uring_get_cqe(&ring, &cqe, 0, 1, NULL);
  printf("ret: %d\n", ret);
  handle_cqe(cqe);
  io_uring_cqe_seen(&ring, cqe);

  handle_ready_cqes(&ring);

  // // wait for cancellation
  // printf("wait for cancellation\n");
  // ret = __io_uring_get_cqe(&ring, &cqe, 0, 1, NULL);
  // printf("ret: %d\n", ret);
  // handle_cqe(cqe);
  // io_uring_cqe_seen(&ring, cqe);

  // // wait for ?
  // printf("wait for cqe\n");
  // ret = __io_uring_get_cqe(&ring, &cqe, 0, 1, NULL);
  // printf("ret: %d\n", ret);

  exit(0);
}

#endif //POLYPHONY_PLAYGROUND
