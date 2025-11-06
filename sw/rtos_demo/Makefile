include $(CURDIR)/sub.mk

TARGET = cnn_demo
OBJS = main.o

CFLAGS += -O2 -Wall -Wextra -I../dsa
LDFLAGS +=

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

main.o: main.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)

.PHONY: all clean
