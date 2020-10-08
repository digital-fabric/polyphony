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

void print(struct io_uring *ring, const char *str) {
  struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
  io_uring_prep_write(sqe, 1, str, strlen(str), -1);
  io_uring_sqe_set_data(sqe, (void *)42);
  // io_uring_sqe_set_flags(sqe, IOSQE_ASYNC);
  io_uring_submit(ring);

  struct io_uring_cqe *cqe;
  int ret = __io_uring_get_cqe(ring, &cqe, 0, 1, NULL);
  if (ret != 0) {
    printf("ret: %d\n", ret);
    exit(1);
  }
  printf("  cqe res: %d\n", cqe->res);
  io_uring_cqe_seen(ring, cqe);
}

noreturn void playground() {
  struct io_uring ring;
  io_uring_queue_init(1024, &ring, 0);

  for (int i = 0; i < 10; i++) {
    print(&ring, "hi\n");
  }

  io_uring_queue_exit(&ring);
  exit(0);
}

#endif //POLYPHONY_PLAYGROUND
