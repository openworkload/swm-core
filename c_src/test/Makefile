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
PORTER_PRIV_OBJ=$(PORTER_DIR)/wm_porter_priv.o

all: $(TARGET)

.PHONY: lib porter-objs
lib:
	$(MAKE) -C $(SWM_C_LIB)

porter-objs: lib
	$(MAKE) -C $(PORTER_DIR) wm_porter_ctrl.o wm_porter_priv.o

%.o: %.cpp
	$(CC) -fPIC -c -o $@ $(CFLAGS) $<

$(TARGET): lib porter-objs $(OBJS)
	$(CC) -o $@ $(OBJS) $(SWM_C_LIB)/*.o $(PORTER_CTRL_OBJ) $(PORTER_PRIV_OBJ) $(LDFLAGS) $(CFLAGS)

clean:
	rm -f ./*.o $(TARGET)
