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
	ts2.tv_nsec = 500 * 1000000;
  printf("sleep 500msec\n");
  nanosleep(&ts2, NULL);

  //cancel
  sqe = io_uring_get_sqe(&ring);
  io_uring_prep_cancel(sqe, (void *)13, 0);
  printf("submit cancel\n");
  io_uring_submit(&ring);

  struct io_uring_cqe *cqe;
  printf("wait for cqe\n");
  int ret = __io_uring_get_cqe(&ring, &cqe, 0, 1, NULL);
  printf("ret: %d\n", ret);

  void *data = io_uring_cqe_get_data(cqe);
  printf("cqe data: %p\n", data);
  printf("cqe res: %d\n", cqe->res);

  exit(0);
}

#endif //POLYPHONY_PLAYGROUND
