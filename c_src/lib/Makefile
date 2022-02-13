
CC=g++
ERL_PATH=${_KERL_ACTIVE_DIR}
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -Werror\
       -pedantic\
       -Wall\
       -Wextra\
       -Wconversion\
       -g\
       -std=c++14
LIBS=-lei\
     -lnsl\
     -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)

all: $(OBJS)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $(CFLAGS) $(LIBS) $<

clean:
	rm -f ./*.o $(TARGET)

