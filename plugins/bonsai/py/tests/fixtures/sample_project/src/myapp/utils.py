import json  # unused import — caught by pyfindunused

from myapp.services import create_user


def bootstrap() -> None:
    create_user(name="admin", email="admin@example.com")
    create_user(name="guest", email="guest@example.com")
