CC=g++
ERL_PATH=${_KERL_ACTIVE_DIR}
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -Werror\
       -pedantic\
       -Wall\
       -Wextra\
       -Wconversion\
       -g\
       -std=c++17\
       -MMD\
       -MP
LIBS=-lei\
     -lnsl\
     -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)
DEPS=$(OBJS:.o=.d)

all: $(OBJS)

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $(CFLAGS) $(LIBS) $<

clean:
	rm -f ./*.o ./*.d $(TARGET)

-include $(DEPS)

