from myapp.models import User


def create_user(name: str, email: str) -> User:
    user = User(name=name, email=email)
    user.save()
    return user


def process(data: str, unused_param: int) -> str:
    """unused_param is never read — caught by pyfindunused."""
    return data.upper()
