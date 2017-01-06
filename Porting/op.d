/* -*- dtrace-script -*- */
#pragma D option quiet

BEGIN {
    self->prev = 0;
}

perl$target:::op-entry {
    myop = copyinstr(arg0);
    curtime = timestamp;
    elapsed = self->prev ? curtime - self->prev : 0;
    @count[myop] = count();
    @time[myop]  = avg(elapsed);
    @quant[myop] = quantize(elapsed);
    self->prev = curtime;
}

END {
    printf("\nOps: (count)\n");
    printa("%10s\t%@8u\n", @count);
    printf("\nTime: (avg ns)\n");
    printa("%10s\t%@8u\n", @time);
    printf("\nQuantize: (value in ns)\n");
    printa("%10s\t%@8u\n", @quant);
}
