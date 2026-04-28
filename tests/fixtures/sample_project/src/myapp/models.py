import os  # unused import — caught by pyfindunused


class User:
    def __init__(self, name: str, email: str) -> None:
        self.name = name
        self.email = email

    def save(self) -> None:
        pass

    def delete(self) -> None:
        pass


class Product:
    """A second class with a .save() method — demonstrates pycallers false positives."""

    def save(self) -> None:
        pass


def _internal_helper() -> str:
    """Private function — must NOT appear in dead-code results."""
    return "helper"


def orphaned_function() -> None:
    """No references anywhere — dead code."""
    pass
