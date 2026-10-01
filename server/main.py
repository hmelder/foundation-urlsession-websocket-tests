import asyncio
import signal
import sys
from websockets.asyncio.server import serve
from websockets.frames import CloseCode

async def echo(websocket):
    try:
        async for message in websocket:
            if isinstance(message, str) and message == "close!":
                # these strings are hard-coded in the Objective-C unit test.
                await websocket.send("closing!")
                print('closing remote connection!')
                await websocket.close(code=CloseCode.NORMAL_CLOSURE, reason='client requested closure')
                break

            await websocket.send(message)

    except asyncio.CancelledError:
        # Connection task was cancelled during shutdown.
        raise


async def main():
    shutdown_event = asyncio.Event()

    if (len(sys.argv) != 3):
        print('please provide the host and port for the WebSocket server')
        return

    def handle_signal():
        print("\nShutdown requested...")
        shutdown_event.set()

    host = sys.argv[1]
    port = sys.argv[2]

    loop = asyncio.get_running_loop()

    # Ctrl+C / SIGTERM
    loop.add_signal_handler(signal.SIGINT, handle_signal)
    loop.add_signal_handler(signal.SIGTERM, handle_signal)

    async with serve(echo, host, port) as server:
        print(f"ws://{host}:{port}")

        # Wait until SIGINT/SIGTERM is received.
        await shutdown_event.wait()

        print("Shutting down WebSocket server...")
        server.close()
        # Wait until the listening socket is actually closed.
        await server.wait_closed()

        print("WebSocket server stopped.")
        exit(0)


if __name__ == "__main__":
    asyncio.run(main())
