TARGET=unittests
CC=g++
ERL_PATH=${_KERL_ACTIVE_DIR}
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I/usr/local/GTest/include\
       -I../lib\
       -L/usr/erlang/usr/lib/\
       -L/usr/local/GTest/lib\
       -Werror\
       -pedantic\
       -Wall\
       -Wextra\
       -Wconversion\
       -g\
       -std=c++17
LDFLAGS=-lei\
        -lnsl\
        -lgtest_main\
        -lgtest\
        -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o) ../lib/*.o ./lib/*.h

all: $(TARGET)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $(CFLAGS) $<

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS) $(CFLAGS)

clean:
	rm -f ./*.o $(TARGET)
