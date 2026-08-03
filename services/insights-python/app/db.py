import os
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row


DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://prompt_user:prompt_pass@localhost:5432/prompt_lab")


@contextmanager
def get_connection():
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as connection:
        yield connection
