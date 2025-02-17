import { ResourceContent } from 'data/content/resource';
import { DragPayload } from '../interfaces';
import * as Immutable from 'immutable';
import * as Persistence from 'data/persistence/activity';

const scrollToResourceEditor = (contentId: string) => {
  setTimeout(() => {
    document.querySelector(`#re${contentId}`)?.scrollIntoView({ behavior: 'smooth' });
  });
};

export const dropHandler =
  (
    content: Immutable.OrderedMap<string, ResourceContent>,
    onEditContentList: (content: Immutable.OrderedMap<string, ResourceContent>) => void,
    projectSlug: string,
    onDragEnd: () => void,
    editMode: boolean,
  ) =>
  (e: React.DragEvent<HTMLDivElement>, index: number) => {
    onDragEnd();

    if (editMode) {
      const data = e.dataTransfer.getData('application/x-oli-resource-content');

      if (data) {
        const droppedContent = JSON.parse(data) as DragPayload;

        const sourceIndex = content.keySeq().findIndex((k) => k === droppedContent.id);

        if (sourceIndex === -1) {
          // This is a cross window drop, we insert it but have to have to
          // ensure that for activities that we create a new activity for
          // tied to this project
          if (droppedContent.type === 'ActivityPayload') {
            if (droppedContent.project !== projectSlug) {
              Persistence.create(
                droppedContent.project,
                droppedContent.activity.typeSlug,
                droppedContent.activity.model,
                [],
              ).then((result: Persistence.Created) => {
                onEditContentList(
                  content
                    .take(index)
                    .concat([[droppedContent.id, droppedContent.reference]])
                    .concat(content.skip(index)),
                );
              });
            } else {
              onEditContentList(
                content
                  .take(index)
                  .concat([[droppedContent.id, droppedContent.reference]])
                  .concat(content.skip(index)),
              );
            }
          } else if (droppedContent.type === 'content') {
            onEditContentList(
              content
                .take(index)
                .concat([[droppedContent.id, droppedContent]])
                .concat(content.skip(index)),
            );
          } else {
            onEditContentList(
              content
                .take(index)
                .concat([[droppedContent.id, droppedContent.data]])
                .concat(content.skip(index)),
            );
          }

          // scroll to inserted item
          scrollToResourceEditor(droppedContent.id);
          return;
        }
        if (sourceIndex > -1) {
          // Handle a same window drag and drop
          const adjusted = sourceIndex < index ? index - 1 : index;

          let toInsert;
          if (droppedContent.type === 'ActivityPayload') {
            toInsert = droppedContent.reference;
          } else if (droppedContent.type === 'content') {
            toInsert = droppedContent;
          } else {
            toInsert = droppedContent.data;
          }

          const prefix = content.delete(droppedContent.id).take(adjusted);
          const suffix = content.delete(droppedContent.id).skip(adjusted);
          const reordered = prefix.concat([[toInsert.id, toInsert]]).concat(suffix);

          onEditContentList(reordered);

          // scroll to moved item
          scrollToResourceEditor(droppedContent.id);
          return;
        }
      }

      // Handle a drag and drop from VSCode
      const text = e.dataTransfer.getData('codeeditors');
      if (text) {
        try {
          const json = JSON.parse(text);
          const parsedContent = JSON.parse(json[0].content);

          // Remove it if we find the same identified content item
          const inserted = content
            .filter((contentItem) => parsedContent.id !== contentItem.id)
            // Then insert it
            .set(parsedContent.id, parsedContent);

          onEditContentList(inserted);

          // scroll to inserted item
          scrollToResourceEditor(parsedContent.id);
        } catch (err) {
          // eslint-disable-next-line
        }
      }
    }
  };
