#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include "./liburing/liburing.h"

void sig_handler(int sig) {
  printf("handle signal %d!\n", sig);
}

int main(int argc, char *argv[])
{
  int pid = getpid();
  int child_pid = fork();
  if (!child_pid) {
    sleep(1);
    kill(pid, SIGINT);
    sleep(1);
    kill(pid, SIGINT);
  }
  else {
    struct sigaction sa;

    sa.sa_handler = sig_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;//0;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGINT, &sa, NULL);

    printf("pid: %d\n", pid);

    struct io_uring ring;
    int ret = io_uring_queue_init(16, &ring, 0);
    printf("io_uring_queue_init: %d\n", ret);

    struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
    io_uring_prep_poll_add(sqe, STDIN_FILENO, POLLIN);
    ret = io_uring_submit(&ring);
    printf("io_uring_submit: %d\n", ret);

    struct io_uring_cqe *cqe;

wait_cqe:
    ret = io_uring_wait_cqe(&ring, &cqe);
    printf("io_uring_wait_cqe: %d\n", ret);
    if (ret == -EINTR) goto wait_cqe;

    printf("done\n");
    return 0;
  }
}
