TARGET=unittests
CC=g++
ERL_PATH=${_KERL_ACTIVE_DIR}
SWM_C_LIB=../lib
PORTER_DIR=../porter
CFLAGS=-I${_KERL_ACTIVE_DIR}/usr/include\
       -I/usr/local/GTest/include\
       -I$(SWM_C_LIB)\
       -I$(PORTER_DIR)\
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
        -lgtest_main\
        -lgtest\
        -lpthread

SRCS=$(shell echo *.cpp)
OBJS=$(SRCS:.cpp=.o)
PORTER_CTRL_OBJ=$(PORTER_DIR)/wm_porter_ctrl.o

all: $(TARGET)

.PHONY: lib porter-ctrl
lib:
	$(MAKE) -C $(SWM_C_LIB)

porter-ctrl: lib
	$(MAKE) -C $(PORTER_DIR) wm_porter_ctrl.o

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $(CFLAGS) $<

$(TARGET): lib porter-ctrl $(OBJS)
	$(CC) -o $@ $(OBJS) $(SWM_C_LIB)/*.o $(PORTER_CTRL_OBJ) $(LDFLAGS) $(CFLAGS)

clean:
	rm -f ./*.o $(TARGET)
