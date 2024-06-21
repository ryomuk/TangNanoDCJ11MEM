#define XCSR_REG_ADDRESS 0177564
#define XBUF_REG_ADDRESS 0177566
#define XCSR_READY (1<<7)

static volatile int *XCSR_REG = (volatile int *) XCSR_REG_ADDRESS;
static volatile int *XBUF_REG = (volatile int *) XBUF_REG_ADDRESS;

int putchar(int c)
{
  while(!(*XCSR_REG & XCSR_READY)){}
  *XBUF_REG = c;
}

int puts(const char *s)
{
  while(*s)
    putchar(*s++);
  return 0;
}

int cstart(){
  int i, x, y;
  double a, b, ca, cb, t;

  puts("\r\n");
  for(y = -12; y <=12; y++){
    for(x = -39; x <= 39; x++){
      ca = x * 0.0458;
      cb = y * 0.08333;
      a = ca;
      b = cb;
      for(i = 0; i <= 15; i++){
        t = a*a - b*b + ca;
        b = 2*a*b + cb;
        a = t;
        if((a*a + b*b) > 4){
          if( i > 9) i=i+7;
          putchar(48+i);
          break;
        } else if(i == 15){
          putchar(' ');
        }
      }
    }
    puts("\r\n");
  }
  while(1);
}
