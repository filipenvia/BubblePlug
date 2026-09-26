"""Ableton Remote Script package for the PlugSpot technical proof."""

from .plugspot import PlugSpot


def create_instance(c_instance):
    """Entry point expected by Live when loading a control surface script."""
    return PlugSpot(c_instance)


__all__ = ["PlugSpot", "create_instance"]
