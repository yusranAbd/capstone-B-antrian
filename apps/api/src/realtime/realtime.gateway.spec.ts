import type { Socket } from 'socket.io';

import { RealtimeGateway } from './realtime.gateway';

describe('RealtimeGateway - fondasi aman', () => {
  let gateway: RealtimeGateway;

  beforeEach(() => {
    gateway = new RealtimeGateway();
  });

  it('menolak koneksi hingga autentikasi JWT tersedia', () => {
    const disconnect = jest.fn();
    const client = { disconnect } as unknown as Socket;

    gateway.handleConnection(client);

    expect(disconnect).toHaveBeenCalledTimes(1);
    expect(disconnect).toHaveBeenCalledWith(true);
  });

  it('tidak memasukkan klien tanpa otorisasi ke room atau mengirim event', () => {
    const disconnect = jest.fn();
    const join = jest.fn();
    const emit = jest.fn();
    const client = { disconnect, join, emit } as unknown as Socket;

    gateway.handleConnection(client);

    expect(join).not.toHaveBeenCalled();
    expect(emit).not.toHaveBeenCalled();
  });
});
