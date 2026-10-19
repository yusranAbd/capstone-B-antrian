import { ArgumentsHost, GoneException } from '@nestjs/common';
import { DisplayErrorFilter } from './display-error.filter';
describe('DisplayErrorFilter credential safety', () => {
  const filter = new DisplayErrorFilter();
  const status = jest.fn(),
    json = jest.fn();
  const host = {
    switchToHttp: () => ({ getResponse: () => ({ status, json }) }),
  } as unknown as ArgumentsHost;
  beforeEach(() => {
    status.mockReset().mockReturnValue({ json });
    json.mockReset();
  });
  it('masks all database/driver details rather than logging a secret-bearing exception', () => {
    filter.catch(new Error('constraint secret-value-do-not-log'), host);
    expect(status).toHaveBeenCalledWith(503);
    expect(JSON.stringify(json.mock.calls)).not.toContain(
      'secret-value-do-not-log',
    );
  });
  it('preserves safe HTTP status and domain message', () => {
    filter.catch(new GoneException('Kode aktivasi sudah digunakan'), host);
    expect(status).toHaveBeenCalledWith(410);
    expect(json).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Kode aktivasi sudah digunakan' }),
    );
  });
});
