"""Ableton Remote Script package for the BubblePlug technical proof."""

from .bubbleplug import BubblePlug


def create_instance(c_instance):
    """Entry point expected by Live when loading a control surface script."""
    return BubblePlug(c_instance)


__all__ = ["BubblePlug", "create_instance"]
