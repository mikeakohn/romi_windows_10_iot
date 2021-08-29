#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

struct _token
{
  const char *buffer;
  int ptr;
  char value[128];
};

int get_token(struct _token *token)
{
  int ptr = 0;

  // Skip whitespace.
  do
  {
    if (token->buffer[token->ptr] == ' ' ||
        token->buffer[token->ptr] == '\n' ||
        token->buffer[token->ptr] == '\r' ||
        token->buffer[token->ptr] == '\t')
    {
      token->ptr++;
      continue;
    }

  } while (0);

  if (token->buffer[token->ptr] == 0) { return -1; }

  while (1)
  {
    if (token->buffer[token->ptr] == ' ' ||
        token->buffer[token->ptr] == '\n' ||
        token->buffer[token->ptr] == '\r' ||
        token->buffer[token->ptr] == '\t' ||
        token->buffer[token->ptr] == 0)
    {
      break;
    }

    token->value[ptr++] = token->buffer[token->ptr++];
  }

  token->value[ptr] = 0;

  return ptr;
}

int get_number(struct _token *token)
{
  if (get_token(token) < 1) { return -1; }

  int value = atoi(token->value);

  printf("get_number()=%d\n", value);

  return value >= 1 ? value : -1;
};

int send_uart_command(HANDLE uart, const char command, struct _token *token)
{
  int count = 0;

  printf("Sending command '%c'\n", command);

  // Using two separate writes to have a little delay.
  if (!WriteFile(uart, &command, 1, &count, NULL))
  {
    printf("Error: WriteFile() to UART failed.\n");
  }

  printf("Wrote %d bytes\n", count);

  int value = get_number(token);
  if (value < 0) { return -1; }
  uint8_t c = value;

  Sleep(1000);

  printf("Sending value %d\n", value);

  if (!WriteFile(uart, &c, 1, &count, NULL))
  {
    printf("Error: WriteFile() to UART failed.\n");
  }

  printf("Wrote %d bytes\n", count);

  return 0;
}

void parse(const char *buffer, HANDLE uart)
{
  struct _token token;
  char data[1];
  int count = 0;

  token.buffer = buffer;
  token.ptr = 0;

  while (1)
  {
    if (get_token(&token) < 1) { break; }

    printf("token='%s'\n", token.value);

    if (strcmp(token.value, "FD") == 0)
    {
      if (send_uart_command(uart, 'f', &token) != 0) { break; }
    }
      else
    if (strcmp(token.value, "BK") == 0)
    {
      if (send_uart_command(uart, 'b', &token) != 0) { break; }
    }
      else
    if (strcmp(token.value, "LT") == 0)
    {
      if (send_uart_command(uart, 'l', &token) != 0) { break; }
    }
      else
    if (strcmp(token.value, "RT") == 0)
    {
      if (send_uart_command(uart, 'r', &token) != 0) { break; }
    }
      else
    {
      printf("Unknown command %s\n", token.value);
      continue;
    }

    printf("Waiting on response...\n");

    // This appears to be blocking.
    if (!ReadFile(uart, data, sizeof(data), &count, NULL))
    {
      printf("Error: ReadFile failed.\n");
      break;
    }

    printf("count=%d\n", count);
  }

  printf("Done\n");
}

int main(int argc, char *argv[])
{
  WSADATA wsaData;
  WORD wVersionRequested = MAKEWORD(1,1);
  int Win32isStupid;

  Win32isStupid = WSAStartup(wVersionRequested, &wsaData);
  if (Win32isStupid)
  {
    printf("Winsock can't start.\n");
    exit(1);
  }

  printf("Open UART...\n");

  HANDLE uart;

  //const char *port = "ACPI\\BCM2836\\0";
  //const char *port = "ACPI\\MINIUART";
  //const char *port = "MINIUART";
  //const char *port = "\\\\?\\ACPI#BCM2836#0";
  const char *port = "\\\\?\\ACPI#BCM2836#0#{86e0d1e0-8089-11d0-9ce4-08003e301f73}";

  uart = CreateFile(
    port,  
    GENERIC_READ | GENERIC_WRITE, 
    0, 
    0, 
    OPEN_EXISTING,
    0,
    0);

  if (uart == INVALID_HANDLE_VALUE)
  {
    printf("Error: Cannot open '%s'.\n", port);
    exit(1);
  }

  DCB uart_settings;

  memset(&uart_settings, 0, sizeof(uart_settings));
  uart_settings.DCBlength = sizeof(uart_settings);

  if (!GetCommState(uart, &uart_settings))
  {
    printf("Error: GetCommState()\n");
    exit(1);
  }

  uart_settings.BaudRate = CBR_9600;
  uart_settings.ByteSize = 8;
  uart_settings.Parity = NOPARITY;
  uart_settings.StopBits = ONESTOPBIT;
  uart_settings.fDtrControl = DTR_CONTROL_DISABLE;

  if (!SetCommState(uart, &uart_settings))
  {
    printf("Error: SetCommState()\n");
    exit(1);
  }

#if 0
  char data = 's';
  int count = 0;

  // Reset device.
  if (!WriteFile(uart, &data, 1, &count, NULL))
  {
    printf("Error: WriteFile() to UART failed.\n");
  }

  // This appears to be blocking.
  if (!ReadFile(uart, &data, 1, &count, NULL))
  {
    printf("Error: ReadFile failed.\n");
  }

  printf("Response: %d\n", data);
#endif

  int sockfd;
  struct sockaddr_in source_addr;
  struct sockaddr dest_addr;
  char buffer[65536];

  printf("Open UDP socket...\n");

  if ((sockfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) < 0)
  {
    printf("Can't open socket.\n");
    exit(1);
  }

  memset(&source_addr, 0, sizeof(source_addr));
  source_addr.sin_family = AF_INET;
  source_addr.sin_port = htons(8000);
  source_addr.sin_addr.s_addr = htonl(INADDR_ANY);

  if (bind(sockfd, (struct sockaddr *)&source_addr, sizeof(source_addr)) < 0)
  {
    printf("Can't bind socket.\n");
    exit(1);
  }

  printf("binding sockfd=%d\n", sockfd);

  int addrlen = sizeof(dest_addr);
  int length = 0;

  do
  {
    memset(&dest_addr, 0, sizeof(dest_addr));
    memset(buffer, 0, sizeof(buffer));

    length = recvfrom(
      sockfd,
      buffer,
      sizeof(buffer),
      0,
      &dest_addr,
      &addrlen);

    printf("length=%d\n", length);
    printf("buffer=%s\n", buffer);

    parse(buffer, uart);
  } while (length > 0);

  close(sockfd);

  return 0;
}

